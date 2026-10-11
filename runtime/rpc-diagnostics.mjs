import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { stat, rename, appendFile } from 'node:fs/promises';

// Fixed fields only: never serialize requests, arguments, results, headers,
// signed URLs, paths, command text or exception messages into diagnostics.
export class RpcDiagnostics {
  constructor(root) { this.file = path.join(root, 'rpc.events.private.jsonl'); this.events = []; this.writes = Promise.resolve(); }
  begin(req, res, input, names) {
    const row = { trace_id: randomUUID(), at: new Date().toISOString(), method: ['initialize', 'notifications/initialized', 'tools/list', 'tools/call', 'ping', 'server/discover'].includes(input?.method) ? input.method : 'other', tool: names.has(input?.params?.name) ? input.params.name : undefined };
    const started = Date.now(); let written = false;
    const finish = disconnected => {
      if (written) return; written = true;
      this.record({ ...row, http_status: res.statusCode, duration_ms: Date.now() - started, disconnected, outcome: row.outcome || (res.statusCode >= 400 ? 'transport_error' : disconnected ? 'response_disconnected' : 'response_sent'), ...(row.code ? { code: row.code } : {}) });
    };
    res.once('finish', () => finish(false)); res.once('close', () => finish(!res.writableFinished));
    return row;
  }
  record(row) {
    this.events.push(row); if (this.events.length > 100) this.events.shift();
    this.writes = this.writes.then(async () => {
      try { if ((await stat(this.file)).size > 2 * 1024 * 1024) await rename(this.file, `${this.file}.previous`); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      await appendFile(this.file, `${JSON.stringify(row)}\n`);
    }).catch(() => {});
  }
  snapshot() { return { scope: 'requests reaching this gateway only', recent: this.events.slice(-20) }; }
}
