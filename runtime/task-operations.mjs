import path from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
import { mkdir, copyFile, writeFile, rename, unlink, open, stat, appendFile } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';

export const VERSION = '1.2.1-local';
const text = (message, data) => ({ content: [{ type: 'text', text: message }], ...(data ? { structuredContent: data } : {}) });
const fail = (code, message, data = {}) => ({ ...text(`${code}: ${message}`, { code, ...data }), isError: true });
const taskId = { type: 'string', description: 'Your own begin_task ID.' };
const requestKey = { type: 'string', description: 'Unique key for one intended operation. On a connection error retry with the SAME key, or query get_operation with it, to avoid repeating a write or command.' };
const tool = (name, description, properties, required) => ({ name, description, inputSchema: { type: 'object', properties: { task_id: taskId, ...properties }, required: ['task_id', ...required] } });
export const operationTools = [
  tool('get_operation', 'Query a background operation without starting it again. A completed operation returns its original tool result. For scripts, output can be read incrementally with output_offset. Keep polling while running; a Chat or tunnel interruption does not stop it.', { operation_id: { type: 'string' }, request_key: requestKey, output_offset: { type: 'integer', minimum: 0 }, output_bytes: { type: 'integer', minimum: 1, maximum: 65536 } }, []),
  tool('task_status', 'Show this task\'s operation IDs and states. Recover operation IDs after a dropped tool response. Does not expose other Chats\' task IDs.', {}, []),
  tool('prepare_file_edit', 'Prepare independent working copies for editing existing files with scripts. Returns edit_id and original/working_copy mappings. Original versions are captured now; publish refuses changes made by another task or external editor.', { files: { type: 'array', items: { type: 'string' }, minItems: 1 }, request_key: requestKey }, ['files']),
  tool('commit_file_edit', 'Publish all prepared working copies after checking their captured original versions. On conflict, copies remain available for merging. Multiple file replacements are individually atomic, not one filesystem transaction.', { edit_id: { type: 'string' }, request_key: requestKey }, ['edit_id']),
  tool('run_file_task', 'Run a long script in the background with optional prepared working copies. LOCAL_ASSISTANT_WORK_FILES contains a JSON array of original/working_copy paths. Edit working_copy paths, never originals; publish=true commits only on exit code 0 with version checks. Returns an operation_id promptly. Use a unique request_key and query get_operation after interruptions.', { command: { type: 'string' }, edit_id: { type: 'string' }, publish: { type: 'boolean', default: false }, shell: { type: 'string', enum: ['powershell', 'cmd'] }, request_key: requestKey }, ['command']),
  {
    ...tool('save_chatgpt_file', 'Save a file created or inspected in ChatGPT\'s own environment to the local computer. Generate and render/view Word, Excel or PDF in ChatGPT first; then pass its file object here. No local OCR or office renderer is used. Read an existing destination before replacing it. qa_report records ChatGPT\'s own inspection; this local tool does not certify visual quality.', {
      file: { type: 'object', properties: { download_url: { type: 'string' }, file_id: { type: 'string' }, mime_type: { type: 'string' }, file_name: { type: 'string' } }, required: ['download_url', 'file_id'] }, destination: { type: 'string' }, qa_report: { type: 'string' }, request_key: requestKey
    }, ['file', 'destination']),
    _meta: { 'openai/fileParams': ['file'] }
  }
];

export class TaskOperations extends EventEmitter {
  constructor(gateway) { super(); this.gateway = gateway; this.jobs = new Map(); this.keys = new Map(); this.edits = new Map(); this.events = []; this.eventWrites = Promise.resolve(); }
  record(kind, job) {
    const event = { at: new Date().toISOString(), kind, task_id: job.task_id, operation_id: job.id, tool: job.tool, state: job.state, ...(job.result?.isError ? { code: job.result.structuredContent?.code || 'TOOL_ERROR' } : {}) };
    this.events.push(event); if (this.events.length > 200) this.events.shift(); this.emit('change');
    const log = path.join(this.gateway.root, 'operations.events.private.jsonl');
    this.eventWrites = this.eventWrites.then(async () => {
      try { if ((await stat(log)).size > 2 * 1024 * 1024) await rename(log, `${log}.previous`); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      await appendFile(log, `${JSON.stringify(event)}\n`);
    }).catch(() => {});
  }
  async call(name, input, execute) {
    const task = this.gateway.tasks.get(input.task_id);
    if (name === 'begin_task' || !task || task.internal) return execute();
    // Existing Chats can still have the old tool catalogue cached. Reuse the
    // already known read_file tool for status queries until their tools refresh.
    if (name === 'read_file' && input.path === 'local-assistant://task/status') return text('Task operation status.', { task_id: task.id, operations: this.rows(task.id) });
    if (name === 'read_file' && input.path === 'local-assistant://capabilities') return text('Live local assistant capabilities.', this.gateway.capabilities());
    if (name === 'read_file' && /^local-assistant:\/\/operations\/[a-f0-9-]+$/i.test(input.path || '')) return this.get(task, { operation_id: input.path.split('/').pop() });
    if (name === 'get_operation') return this.get(task, input);
    if (name === 'task_status') return text('Task operation status.', { task_id: task.id, work_directory: task.work, operations: this.rows(task.id) });
    if (name === 'end_task') return execute();
    const key = input.request_key ? `${task.id}:${String(input.request_key)}` : null;
    if (key && this.keys.has(key)) {
      const old = this.jobs.get(this.keys.get(key));
      // An explicit idempotency key must describe the same intended operation.
      if (old.tool !== name || old.fingerprint !== this.fingerprint(input)) return fail('REQUEST_KEY_REUSED', 'Use a new request_key for a different operation.');
      return this.result(old);
    }
    const job = { id: randomUUID(), task_id: task.id, tool: name, state: 'running', started_at: new Date().toISOString(), fingerprint: this.fingerprint(input), abort: new AbortController(), child: null };
    this.jobs.set(job.id, job); if (key) this.keys.set(key, job.id);
    this.record('started', job);
    job.promise = (async () => {
      try {
        if (['prepare_file_edit', 'commit_file_edit', 'run_file_task', 'save_chatgpt_file'].includes(name)) {
          task.pending++;
          try { job.result = await this.extra(task, name, input, job); }
          finally { task.pending--; task.lastUsed = Date.now(); }
        } else job.result = await execute(job.abort.signal);
      } catch (error) {
        // Avoid retaining signed file URLs, command text, or credentials in diagnostics.
        job.result = fail(job.abort.signal.aborted ? 'OPERATION_CANCELLED' : 'LOCAL_OPERATION_ERROR', name === 'save_chatgpt_file' ? 'File download/save failed. Ask ChatGPT for a fresh file URL and retry with a new request_key.' : String(error.message || error).replace(/https?:\/\/\S+/g, '[URL]'));
      }
      job.state = job.result.isError ? 'failed' : 'completed'; job.finished_at = new Date().toISOString(); this.record('finished', job);
      return job.result;
    })();
    // The HTTP request never owns the operation lifetime. Locks, hashing, scripts
    // and file downloads continue even if the caller disconnects or cancels HTTP.
    let timer;
    await Promise.race([job.promise, new Promise(resolve => { timer = setTimeout(resolve, 900); })]);
    clearTimeout(timer);
    return this.result(job);
  }
  fingerprint(input) {
    const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
    const clean = { ...input }; delete clean.request_key;
    return createHash('sha256').update(JSON.stringify(canonical(clean))).digest('hex');
  }
  result(job) {
    const data = { operation_id: job.id, operation_state: job.state, task_id: job.task_id };
    if (job.state === 'running') return text(`Operation continues in the background. operation_id=${job.id}. Query get_operation with this task_id and operation_id. If your older Chat has no get_operation tool, call read_file with task_id=${job.task_id} and path="local-assistant://operations/${job.id}". You can list this task's operations with read_file(path="local-assistant://task/status", task_id). Do not start the same command/write again.`, data);
    return { ...job.result, structuredContent: { ...(job.result.structuredContent || {}), ...data } };
  }
  async get(task, input) {
    const id = input.operation_id || this.keys.get(`${task.id}:${String(input.request_key)}`);
    const job = this.jobs.get(id);
    if (!job || job.task_id !== task.id) return fail('OPERATION_NOT_FOUND', 'No such operation in this task. Use task_status to list your operations.');
    const result = this.result(job);
    if (job.log) {
      let handle;
      try {
        handle = await open(job.log, 'r'); const length = (await handle.stat()).size;
        const offset = Math.min(Math.max(0, Number(input.output_offset || 0)), length);
        const buffer = Buffer.alloc(Math.min(Number(input.output_bytes || 16384), 65536, length - offset));
        const { bytesRead } = await handle.read(buffer, 0, buffer.length, offset);
        result.structuredContent = { ...result.structuredContent, output: buffer.subarray(0, bytesRead).toString('utf8'), next_output_offset: offset + bytesRead, output_total_bytes: length, output_file: job.log };
        if (bytesRead) result.content = [...result.content, { type: 'text', text: buffer.subarray(0, bytesRead).toString('utf8') }];
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
      finally { await handle?.close(); }
    }
    return result;
  }
  rows(taskId) { return [...this.jobs.values()].filter(j => !taskId || j.task_id === taskId).map(j => ({ operation_id: j.id, task_id: j.task_id, tool: j.tool, state: j.state, started_at: j.started_at, finished_at: j.finished_at, pid: j.child?.pid, code: j.result?.isError ? j.result.structuredContent?.code || 'TOOL_ERROR' : undefined })); }
  assertActive(task, job) { if (task.closed || job?.abort.signal.aborted) throw new Error('Task or operation has been stopped.'); }
  async extra(task, name, input, job) {
    this.assertActive(task, job);
    if (name === 'prepare_file_edit') return this.prepare(task, input.files);
    if (name === 'commit_file_edit') return this.publish(task, input.edit_id, job);
    if (name === 'run_file_task') return this.run(task, input, job);
    if (name === 'save_chatgpt_file') return this.saveCloudFile(task, input, job);
  }
  async prepare(task, files) {
    const originals = await Promise.all(files.map(file => this.gateway.absolute(task, file)));
    if (new Set(originals.map(f => this.gateway.key(f))).size !== originals.length) return fail('DUPLICATE_FILE', 'List each destination once.');
    await this.gateway.validatePaths(task, originals);
    return this.gateway.locked(originals, async () => {
      this.assertActive(task);
      const id = randomUUID(), directory = path.join(task.work, 'edits', id); await mkdir(directory, { recursive: true });
      const mappings = [];
      for (let i = 0; i < originals.length; i++) {
        const original = originals[i], working_copy = path.join(directory, `${i + 1}-${path.basename(original)}`), version = await this.gateway.version(original);
        if (version?.startsWith('directory:')) return fail('FILE_REQUIRED', 'Working copies require files, not directories.');
        if (version === null) await writeFile(working_copy, ''); else await copyFile(original, working_copy);
        if (await this.gateway.version(original) !== version || (version !== null && await this.gateway.version(working_copy) !== version)) return fail('FILE_CONFLICT', 'A file changed while copying it. Prepare again.');
        mappings.push({ original, working_copy, version }); task.versions.set(this.gateway.key(original), version);
      }
      this.edits.set(id, { id, task_id: task.id, mappings, busy: false, published: false });
      return text('Working copies prepared. Edit the working_copy paths, then run_file_task with publish=true or call commit_file_edit.', { edit_id: id, files: mappings.map(({ version, ...file }) => file) });
    });
  }
  edit(task, id) { const edit = this.edits.get(id); if (!edit || edit.task_id !== task.id) throw new Error('No such edit_id in this task.'); return edit; }
  async publish(task, id, job, reserved = false) {
    const edit = this.edit(task, id);
    if (edit.published) return fail('EDIT_ALREADY_PUBLISHED', 'Prepare a new edit for another change.');
    if (edit.busy && !reserved) return fail('EDIT_BUSY', 'This working copy is being used by a script or commit.');
    if (!reserved) edit.busy = true;
    const temporary = [], published = [];
    try {
      return await this.gateway.locked(edit.mappings.flatMap(f => [f.original, f.working_copy]), async () => {
        this.assertActive(task, job);
        for (const file of edit.mappings) {
          if (await this.gateway.version(file.original) !== file.version) return fail('FILE_CONFLICT', 'An original changed since preparation. Merge into fresh working copies; existing copies remain available.', { files: edit.mappings.map(({ version, ...f }) => f) });
          const sourceVersion = await this.gateway.version(file.working_copy);
          if (!sourceVersion || sourceVersion.startsWith('directory:')) return fail('WORKING_COPY_MISSING', 'A prepared working copy is missing or is not a file.');
          const target = path.join(path.dirname(file.original), `.${path.basename(file.original)}.${randomUUID()}.tmp`);
          temporary.push(target); await copyFile(file.working_copy, target);
          if (await this.gateway.version(file.working_copy) !== sourceVersion || await this.gateway.version(target) !== sourceVersion) return fail('FILE_CONFLICT', 'A working copy changed while publishing.');
        }
        // Recheck the whole set before any replacement, and each file immediately
        // before rename. An external application does not participate in our locks.
        for (const file of edit.mappings) if (await this.gateway.version(file.original) !== file.version) return fail('FILE_CONFLICT', 'An original changed while publishing. No files were replaced.');
        for (let i = 0; i < edit.mappings.length; i++) {
          this.assertActive(task, job); const file = edit.mappings[i];
          if (await this.gateway.version(file.original) !== file.version) return fail('FILE_CONFLICT', 'An external edit occurred between replacements. Inspect published_files before merging.', { published_files: published });
          await rename(temporary[i], file.original); published.push(file.original);
          task.versions.set(this.gateway.key(file.original), await this.gateway.version(file.original));
        }
        edit.published = true;
        return text('Prepared files published with version checks.', { published_files: published });
      });
    } catch (error) {
      return fail('PUBLISH_FAILED', String(error.message).replace(/https?:\/\/\S+/g, '[URL]'), { published_files: published });
    } finally { await Promise.all(temporary.map(f => unlink(f).catch(() => {}))); if (!reserved) edit.busy = false; }
  }
  async run(task, input, job) {
    const edit = input.edit_id ? this.edit(task, input.edit_id) : null;
    if (input.publish && !edit) return fail('EDIT_REQUIRED', 'publish=true requires edit_id from prepare_file_edit.');
    if (edit?.busy || edit?.published) return fail('EDIT_BUSY', 'Use a fresh, idle edit.');
    if (edit) edit.busy = true;
    const env = { ...process.env, LOCAL_ASSISTANT_WORK_FILES: JSON.stringify(edit?.mappings.map(({ version, ...file }) => file) || []), LOCAL_ASSISTANT_TASK_WORK: task.work };
    delete env.CONTROL_PLANE_API_KEY; delete env.AUDIT_ONLY_TUNNEL_KEY;
    const directory = path.join(task.work, 'operations'); await mkdir(directory, { recursive: true });
    job.log = path.join(directory, `${job.id}.log`);
    const stream = createWriteStream(job.log); let streamError;
    stream.on('error', error => { streamError = error; if (job.child) void this.stopChild(job); });
    try {
      this.assertActive(task, job);
      const executable = input.shell === 'cmd' ? (process.env.ComSpec || 'cmd.exe') : path.join(process.env.WINDIR || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe');
      const args = input.shell === 'cmd' ? ['/d', '/s', '/c', input.command] : ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', `[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); ${input.command}`];
      const child = spawn(executable, args, { cwd: task.work, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      job.child = child; this.record('process_started', job);
      child.stdout.pipe(stream, { end: false }); child.stderr.pipe(stream, { end: false });
      const stop = () => { void this.stopChild(job); }; job.abort.signal.addEventListener('abort', stop, { once: true });
      let code;
      try { code = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', resolve); }); }
      finally { job.abort.signal.removeEventListener('abort', stop); await new Promise(resolve => { if (stream.destroyed) resolve(); else stream.end(resolve); }); }
      this.assertActive(task, job);
      if (streamError) throw streamError;
      if (code !== 0) return fail('PROCESS_FAILED', `Script exited with code ${code}. Originals were not published. Read the operation output.`, { exit_code: code, output_file: job.log });
      if (input.publish) return await this.publish(task, edit.id, job, true);
      return text('Background script finished.', { exit_code: code, output_file: job.log, ...(edit ? { edit_id: edit.id } : {}) });
    } finally { if (edit) edit.busy = false; if (!stream.destroyed && !stream.writableEnded) stream.end(); }
  }
  async saveCloudFile(task, input, job) {
    const url = new URL(input.file.download_url);
    if (url.protocol !== 'https:') return fail('HTTPS_REQUIRED', 'ChatGPT file download_url must use HTTPS.');
    const destination = await this.gateway.absolute(task, input.destination); await this.gateway.validatePaths(task, [destination]);
    const checked = await this.gateway.locked([destination], () => this.gateway.checkWrite(task, [destination], false)); if (checked) return checked;
    const expected = task.versions.get(this.gateway.key(destination)) ?? null;
    const directory = path.join(task.work, 'chatgpt-files'); await mkdir(directory, { recursive: true });
    const source = path.join(directory, `${job.id}-${path.basename(destination)}`);
    const signal = AbortSignal.any([job.abort.signal, AbortSignal.timeout(30 * 60 * 1000)]);
    const response = await fetch(url, { signal });
    if (!response.ok || !response.body || new URL(response.url).protocol !== 'https:') return fail('FILE_DOWNLOAD_FAILED', 'The ChatGPT file URL failed or expired. Request a fresh file URL.');
    await pipeline(Readable.fromWeb(response.body), createWriteStream(source), { signal });
    this.assertActive(task, job);
    // Preserve the observed destination version across download time, even if a
    // concurrent read in this task changes task.versions in the meantime.
    const result = await this.gateway.commit(task, { source, destination }, false, { expected, backup: false });
    if (!result.isError) result.structuredContent = { ...result.structuredContent, bytes: (await stat(source)).size, qa_source: 'ChatGPT environment (self-reported)', qa_report: String(input.qa_report || 'No inspection report supplied.') };
    return result;
  }
  async stopChild(job) {
    const child = job.child; if (!child?.pid || child.exitCode !== null || child.signalCode !== null) return;
    if (process.platform === 'win32') await new Promise(resolve => { const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); killer.once('close', resolve); killer.once('error', resolve); });
    else child.kill('SIGTERM');
  }
  async stopTask(task) {
    for (const job of this.jobs.values()) if (job.task_id === task.id && job.state === 'running') { job.abort.abort(); await this.stopChild(job); }
  }
  forget(taskId) {
    for (const [id, job] of this.jobs) if (job.task_id === taskId && job.state !== 'running') this.jobs.delete(id);
    for (const [key, id] of this.keys) if (!this.jobs.has(id)) this.keys.delete(key);
    for (const [id, edit] of this.edits) if (edit.task_id === taskId) this.edits.delete(id);
  }
}
