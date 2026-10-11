import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { VERSION } from './task-operations.mjs';

export async function createLocalStatus(root, gateway, instance) {
  const template = await readFile(path.join(root, 'status-ui.html'), 'utf8');
  const script = await readFile(path.join(root, 'status-ui.js'), 'utf8');
  const subscribers = new Set(); let connection = null;
  const snapshot = () => ({ version: VERSION, tool_count: gateway.listTools().length, diagnostics: gateway.diagnostics?.snapshot(), gateway_pid: process.pid, uptime_seconds: Math.floor(process.uptime()), connection, tasks: [...gateway.tasks.values()].filter(t => !t.internal).map(t => ({ task_id: t.id, label: t.label, work_directory: t.work, pending: t.pending, backend_pid: t.transport?.pid, backend_disconnected_at: t.backend_disconnected_at })), operations: gateway.operations.rows(), events: gateway.operations.events.slice(-40) });
  const broadcast = () => { const data = `data: ${JSON.stringify(snapshot())}\n\n`; for (const response of subscribers) { if (response.destroyed || response.writableEnded) subscribers.delete(response); else response.write(data); } };
  gateway.operations.on('change', broadcast);
  const powershell = (file, background = false) => {
    const executable = path.join(process.env.WINDIR || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
    const child = spawn(executable, ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', path.join(root, file)], { cwd: root, windowsHide: true, detached: background, stdio: background ? 'ignore' : ['ignore', 'pipe', 'pipe'] });
    if (background) { child.on('error', () => {}); child.unref(); return Promise.resolve(); }
    return new Promise((resolve, reject) => {
      let output = ''; const timer = setTimeout(() => { child.kill(); reject(new Error('Status command timed out.')); }, 30000);
      child.stdout.on('data', chunk => { output += chunk; }); child.stderr.resume();
      child.on('error', error => { clearTimeout(timer); reject(error); });
      child.on('close', code => { clearTimeout(timer); if (code !== 0) reject(new Error('Status command failed.')); else { try { resolve(JSON.parse(output.replace(/^\uFEFF/, ''))); } catch { reject(new Error('Status command returned unexpected output.')); } } });
    });
  };
  const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'", 'Referrer-Policy': 'no-referrer' };
  const json = (res, code, data) => { res.writeHead(code, { ...headers, 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data)); };
  return {
    async handle(req, res, url, port) {
      if (!['/', '/ui', '/status-ui.js', '/events', '/api/status', '/api/connection', '/api/action'].includes(url.pathname)) return false;
      const expected = [`127.0.0.1:${port}`, `localhost:${port}`];
      if (!expected.includes(req.headers.host) || req.headers['sec-fetch-site'] === 'cross-site' || (req.headers.origin && !expected.map(h => `http://${h}`).includes(req.headers.origin))) { json(res, 403, { error: 'Local status page only.' }); return true; }
      try {
        if (req.method === 'GET' && ['/', '/ui'].includes(url.pathname)) { res.writeHead(200, { ...headers, 'Content-Type': 'text/html; charset=utf-8' }); res.end(template.replace('INSTANCE_PLACEHOLDER', instance)); }
        else if (req.method === 'GET' && url.pathname === '/status-ui.js') { res.writeHead(200, { ...headers, 'Content-Type': 'text/javascript; charset=utf-8' }); res.end(script); }
        else if (req.method === 'GET' && url.pathname === '/events') { res.writeHead(200, { ...headers, 'Content-Type': 'text/event-stream', Connection: 'keep-alive' }); res.write('retry: 5000\n'); subscribers.add(res); res.write(`data: ${JSON.stringify(snapshot())}\n\n`); res.on('close', () => subscribers.delete(res)); res.on('error', () => subscribers.delete(res)); }
        else if (req.method === 'GET' && url.pathname === '/api/status') json(res, 200, snapshot());
        else if (req.method === 'GET' && url.pathname === '/api/connection') {
          const status = await powershell('Status-LocalFiles.ps1');
          // Display only these explicit status fields; never relay CLI profiles,
          // tunnel identifiers or credentials into a web page.
          connection = Object.fromEntries(['process_running', 'healthy', 'ready', 'controlPlanePoll', 'gatewayHealthy', 'tunnelBindingMatches', 'bindingReason', 'supervisor_running', 'supervisor_state', 'keeper_running', 'guardian_running', 'autostart'].map(key => [key, status[key]]));
          broadcast(); json(res, 200, snapshot());
        } else if (req.method === 'POST' && url.pathname === '/api/action') {
          if (req.headers['x-local-assistant-instance'] !== instance || !req.headers['content-type']?.startsWith('application/json')) { json(res, 403, { error: 'Invalid local action.' }); return true; }
          let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 8192) throw new Error('Action body too large.'); }
          const input = JSON.parse(body);
          if (input.action === 'stop_operation') {
            const job = gateway.operations.jobs.get(input.operation_id);
            if (!job || job.state !== 'running') throw new Error('No running operation with that ID.');
            job.abort.abort(); await gateway.operations.stopChild(job);
          } else if (input.action === 'end_task') {
            const task = gateway.tasks.get(input.task_id); if (!task || task.internal) throw new Error('No such task.');
            const result = await gateway.end(task, input.force === true); if (result.isError) { json(res, 409, result); return true; }
          } else if (input.action === 'restore_connection') await powershell('Start-LocalFiles.ps1', true);
          else if (input.action === 'stop_connection') await powershell('Stop-LocalFiles.ps1', true);
          else throw new Error('Unknown action.');
          json(res, 200, { accepted: true });
        } else json(res, 405, { error: 'Method not allowed.' });
      } catch (error) { if (!res.headersSent) json(res, 400, { error: String(error.message).replace(/https?:\/\/\S+/g, '[URL]') }); }
      return true;
    },
    close() { gateway.operations.off('change', broadcast); for (const res of subscribers) res.end(); subscribers.clear(); }
  };
}
