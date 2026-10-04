import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { CallToolRequestSchema, ListToolsRequestSchema, LATEST_PROTOCOL_VERSION } from '@modelcontextprotocol/sdk/types.js';
import { TaskGateway, INSTRUCTIONS } from './task-gateway-core.mjs';
const root = path.dirname(fileURLToPath(import.meta.url));
const settings = JSON.parse((await readFile(path.join(root, 'settings.private.json'), 'utf8')).replace(/^\uFEFF/, ''));
const instance = randomUUID();
const gateway = new TaskGateway(root, settings);
await gateway.init();
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1');
  if (url.pathname === '/health') { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ healthy: true, version: '1.1.0', instance, pid: process.pid, tasks: gateway.tasks.size - 1 })); return; }
  if (url.pathname === '/shutdown' && req.method === 'POST' && req.headers['x-local-assistant-instance'] === instance) { res.writeHead(200).end('{}'); setImmediate(shutdown); return; }
  if (url.pathname !== '/mcp') { res.writeHead(404).end(); return; }
  if (req.method !== 'POST') { res.writeHead(405).end(); return; }
  // Current tunnel callers may use the newer self-contained MCP envelope. The
  // pinned SDK handles the same tools/initialize JSON-RPC methods but validates
  // only its negotiated transport version. Keep the caller's _meta untouched.
  const callerVersion = req.headers['mcp-protocol-version'];
  if (typeof callerVersion === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(callerVersion) && callerVersion >= '2026-07-28') {
    req.headers['mcp-protocol-version'] = LATEST_PROTOCOL_VERSION;
    // The Node-to-Web adapter reads rawHeaders, not just headers.
    for (let i = 0; i < req.rawHeaders.length; i += 2) if (req.rawHeaders[i].toLowerCase() === 'mcp-protocol-version') req.rawHeaders[i + 1] = LATEST_PROTOCOL_VERSION;
  }
  // This endpoint always replies with JSON. Tunnel discovery probes sometimes
  // omit the SDK's dual Accept values; normalise content negotiation only.
  req.headers.accept = 'application/json, text/event-stream';
  let foundAccept = false;
  for (let i = 0; i < req.rawHeaders.length; i += 2) if (req.rawHeaders[i].toLowerCase() === 'accept') { req.rawHeaders[i + 1] = req.headers.accept; foundAccept = true; }
  if (!foundAccept) req.rawHeaders.push('Accept', req.headers.accept);
  const mcp = new Server({ name: 'local-computer-assistant', version: '1.1.0' }, { capabilities: { tools: {} }, instructions: INSTRUCTIONS });
  if (process.env.LOCAL_ASSISTANT_TEST_DIAGNOSTICS === '1') mcp.onerror = error => console.error(`MCP validation: ${error.message}`);
  mcp.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: gateway.listTools() }));
  mcp.setRequestHandler(CallToolRequestSchema, async request => gateway.call(request.params.name, request.params.arguments));
  const port = server.address().port;
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true, allowedHosts: [`127.0.0.1:${port}`, `localhost:${port}`], enableDnsRebindingProtection: true });
  res.on('close', () => { transport.close().catch(() => {}); mcp.close().catch(() => {}); });
  try { await mcp.connect(transport); await transport.handleRequest(req, res); }
  catch { if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'application/json' }).end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32603, message: 'Local gateway request failed' } })); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
await writeFile(path.join(root, 'gateway.state.private.json'), JSON.stringify({ pid: process.pid, instance, base, mcpUrl: `${base}/mcp`, version: '1.1.0' }));
const timer = setInterval(() => gateway.reap().catch(() => {}), 10 * 60 * 1000); timer.unref();
let closing = false;
async function shutdown() {
  if (closing) return; closing = true; clearInterval(timer);
  server.close(); await gateway.close(); server.closeAllConnections(); process.exit(0);
}
process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);
console.log('Concurrent local gateway ready.');
