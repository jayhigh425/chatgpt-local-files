import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { mkdir, readFile, writeFile, realpath, stat, copyFile, rename, unlink } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';

export const INSTRUCTIONS = `You are connected to the user's local computer through a concurrent task gateway.
At the beginning of EACH independent Chat task call begin_task ONCE. Keep the returned task_id private to that task and include it in EVERY local tool call. Never reuse a task_id from another conversation. If a task expired or the server restarted, call begin_task again.
Each task has an independent Desktop Commander process, config, process/search registry and default working/output directory. All configured disk and command capabilities remain available; use absolute paths for user files. Relative paths are relative to this task's work directory.
Before changing an existing file, read_file (or get_file_info) in this task. File writes compare the current file version with the version this task observed. On FILE_CONFLICT read the latest file and merge/reapply your change. Do not set overwrite_conflict unless the user explicitly wants to discard intervening changes.
Use your OWN PID and search ID. start_process/interact_with_process/read_process_output return promptly while the process continues; poll its PID for more results. Commands should write new outputs into the task work directory. To edit existing files with a script, produce a working copy and use commit_file to publish it with a file-version check. Arbitrary commands retain their full capabilities and can bypass file-tool conflict checks; never concurrently target the same existing file with unmanaged commands.
When the work and its processes are finished call end_task. This closes the task's backend, not another task. Tool results work without a UI widget.`;

const asText = r => (r?.content ?? []).filter(x => x.type === 'text').map(x => x.text).join('\n');
const ok = (text, structuredContent) => ({ content: [{ type: 'text', text }], ...(structuredContent ? { structuredContent } : {}) });
const failure = (code, message) => ({ isError: true, content: [{ type: 'text', text: `${code}: ${message}` }], structuredContent: { code } });
const pause = ms => new Promise(r => setTimeout(r, ms));
const isUrl = value => typeof value === 'string' && /^https?:\/\//i.test(value);

export class TaskGateway {
  constructor(root, settings) {
    this.root = root; this.settings = settings;
    this.tasks = new Map(); this.locks = new Map(); this.catalogue = null;
    this.tasksRoot = path.join(root, 'tasks');
  }
  async init() {
    this.catalogue = await this.createTask('Tool catalogue', true);
    this.tools = (await this.backend(this.catalogue)).tools;
  }
  async createTask(label, internal = false) {
    const id = randomUUID();
    const base = path.join(this.tasksRoot, id);
    const work = this.settings.accessMode === 'Full' ? path.join(base, 'work') : path.join(this.settings.allowedDirectories[0], '.chatgpt-local-tasks', id);
    const configDir = path.join(base, 'config');
    await mkdir(work, { recursive: true }); await mkdir(configDir, { recursive: true });
    const task = { id, label, work, configDir, versions: new Map(), lastUsed: Date.now(), internal, pending: 0, client: null, transport: null, workerPromise: null };
    let baseConfig = {};
    try {
      const userHome = this.settings.configHome || process.env.USERPROFILE;
      baseConfig = JSON.parse((await readFile(path.join(userHome, '.claude-server-commander/config.json'), 'utf8')).replace(/^\uFEFF/, ''));
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
    delete baseConfig.clientId; delete baseConfig.currentClient;
    baseConfig.allowedDirectories = this.settings.accessMode === 'Full' ? [] : this.settings.allowedDirectories;
    baseConfig.blockedCommands = this.settings.accessMode === 'Full' ? [] : (baseConfig.blockedCommands ?? []);
    baseConfig.telemetryEnabled = false;
    baseConfig.defaultShell ||= 'powershell.exe';
    baseConfig.welcomeOnboardingEligible = false; baseConfig.pendingWelcomeOnboarding = false;
    await writeFile(path.join(configDir, 'config.json'), JSON.stringify(baseConfig));
    this.tasks.set(id, task); return task;
  }
  async backend(task) {
    if (!task.workerPromise) task.workerPromise = (async () => {
      const client = new Client({ name: 'local-assistant-task', version: '1.1.0' });
      const env = { ...process.env, LOCAL_ASSISTANT_CONFIG_DIR: task.configDir, DESKTOP_COMMANDER_DISABLE_TELEMETRY: '1', DO_NOT_TRACK: '1' };
      // The model/tool process never receives the tunnel credential.
      delete env.CONTROL_PLANE_API_KEY; delete env.AUDIT_ONLY_TUNNEL_KEY;
      const transport = new StdioClientTransport({ command: this.settings.nodeExecutable || process.execPath, args: [path.join(this.root, 'node_modules/@wonderwhy-er/desktop-commander/dist/index.js'), '--no-onboarding'], cwd: task.work, env, stderr: 'pipe' });
      transport.stderr?.on('data', () => {});
      client.onerror = () => {};
      await client.connect(transport);
      task.client = client; task.transport = transport;
      const tools = (await client.listTools()).tools;
      return { client, tools };
    })();
    return task.workerPromise;
  }
  listTools() {
    const extras = [
      { name: 'begin_task', description: 'Start one independent local task for this Chat. Call once per task; never reuse another conversation\'s ID. Returns task_id and an independent work directory.', inputSchema: { type: 'object', properties: { label: { type: 'string', description: 'Short purpose, no secrets.' } } } },
      { name: 'end_task', description: 'Close this task after its processes finish. Does not affect other tasks. force explicitly stops this task and its descendants.', inputSchema: { type: 'object', properties: { task_id: { type: 'string' }, force: { type: 'boolean', default: false } }, required: ['task_id'] } },
      { name: 'commit_file', description: 'Publish a script-generated working copy to a target file with an observed-version check. Read target in this task before replacing an existing target. Retains a backup of the prior target.', inputSchema: { type: 'object', properties: { task_id: { type: 'string' }, source: { type: 'string' }, destination: { type: 'string' }, overwrite_conflict: { type: 'boolean', default: false, description: 'Use only when user explicitly requests discarding newer edits.' } }, required: ['task_id', 'source', 'destination'] } }
    ];
    return [...extras, ...this.tools.map(tool => {
      const { _meta, ...plain } = tool;
      const schema = structuredClone(tool.inputSchema);
      schema.properties ||= {}; schema.properties.task_id = { type: 'string', description: 'Your begin_task ID. Never borrow an ID from another Chat.' };
      schema.required = [...new Set([...(schema.required ?? []), 'task_id'])];
      if (['write_file', 'write_pdf', 'edit_block', 'move_file'].includes(tool.name)) schema.properties.overwrite_conflict = { type: 'boolean', default: false, description: 'Only for an explicit user request to overwrite newer changes. Otherwise read latest and merge.' };
      return { ...plain, description: `Independent local task. Requires your task_id. ${plain.description || ''}`, inputSchema: schema };
    })];
  }
  async absolute(task, value) {
    if (isUrl(value)) return value;
    const full = path.resolve(task.work, value);
    try { return await realpath(full); }
    catch (e) {
      if (e.code !== 'ENOENT' && e.code !== 'ENOTDIR') throw e;
      let parent = path.dirname(full); const segments = [path.basename(full)];
      while (parent !== path.dirname(parent)) {
        try { return path.join(await realpath(parent), ...segments); }
        catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error; segments.unshift(path.basename(parent)); parent = path.dirname(parent); }
      }
      return full;
    }
  }
  key(file) { return process.platform === 'win32' ? file.toLowerCase() : file; }
  async version(file) {
    try {
      const info = await stat(file);
      if (info.isDirectory()) return `directory:${info.birthtimeMs}`;
      const hash = createHash('sha256');
      for await (const chunk of createReadStream(file)) hash.update(chunk);
      return hash.digest('hex');
    } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
  }
  async locked(files, action) {
    const keys = [...new Set(files.filter(x => !isUrl(x)).map(x => this.key(x)))].sort();
    const releases = [];
    try {
      for (const key of keys) {
        const previous = this.locks.get(key) || Promise.resolve();
        let release; const current = new Promise(r => { release = r; });
        this.locks.set(key, current); await previous;
        releases.push(() => { release(); if (this.locks.get(key) === current) this.locks.delete(key); });
      }
      return await action();
    } finally { for (const release of releases.reverse()) release(); }
  }
  async checkWrite(task, files, force) {
    for (const file of files) {
      const current = await this.version(file); const key = this.key(file);
      if (force || current === null) continue;
      if (!task.versions.has(key)) return failure('READ_REQUIRED', `Read the existing file in this task before saving it: ${file}`);
      if (task.versions.get(key) !== current) return failure('FILE_CONFLICT', `This file changed since this task observed it. Read the latest content and merge/reapply your change: ${file}`);
    }
    return null;
  }
  async validatePaths(task, files) {
    // Respect a recipient-selected directory scope. Full mode has no directory restrictions.
    if (this.settings.accessMode === 'Full') return;
    const roots = await Promise.all(this.settings.allowedDirectories.map(p => this.absolute(task, p)));
    for (const file of files) if (!roots.some(root => this.key(file) === this.key(root) || this.key(file).startsWith(this.key(root) + path.sep))) throw new Error('Path is outside this recipient\'s selected directories.');
  }
  async call(name, input = {}) {
    if (name === 'begin_task') {
      const task = await this.createTask(String(input.label || 'Chat task').slice(0, 120));
      return ok(`Task started. task_id=${task.id}\nwork_directory=${task.work}\nUse this task_id for every local call in this Chat task.`, { task_id: task.id, work_directory: task.work });
    }
    const task = this.tasks.get(input.task_id);
    if (!task || task.internal) return failure('TASK_REQUIRED', 'Call begin_task in this Chat and pass its task_id; the prior task may have expired or the server restarted.');
    task.lastUsed = Date.now(); task.pending++;
    try {
      if (name === 'end_task') return await this.end(task, input.force === true);
      const args = { ...input }; delete args.task_id; delete args.overwrite_conflict;
      for (const field of ['path', 'file_path', 'source', 'destination', 'outputPath']) if (typeof args[field] === 'string') args[field] = await this.absolute(task, args[field]);
      if (Array.isArray(args.paths)) args.paths = await Promise.all(args.paths.map(p => this.absolute(task, p)));
      const paths = ['path', 'file_path', 'source', 'destination', 'outputPath'].map(k => args[k]).filter(x => typeof x === 'string' && !isUrl(x));
      paths.push(...(args.paths ?? []).filter(x => !isUrl(x)));
      await this.validatePaths(task, paths);
      if (name === 'commit_file') return await this.commit(task, args, input.overwrite_conflict === true);
      const { client } = await this.backend(task);
      if (['start_process', 'read_process_output', 'interact_with_process'].includes(name)) args.timeout_ms = Math.min(Math.max(Number(args.timeout_ms ?? 1000), 1), 1000);
      const readNames = ['read_file', 'read_multiple_files', 'get_file_info'];
      let targets = [];
      if (name === 'write_file') targets = [args.path];
      if (name === 'edit_block') targets = [args.file_path];
      if (name === 'write_pdf') targets = [args.outputPath || args.path];
      if (name === 'move_file') targets = [args.source, args.destination];
      const lockPaths = readNames.includes(name) ? paths : targets;
      return await this.locked(lockPaths, async () => {
        if (targets.length && !(name === 'write_file' && args.mode === 'append')) {
          const error = await this.checkWrite(task, targets, input.overwrite_conflict === true);
          if (error) return error;
        }
        const before = new Map();
        if (readNames.includes(name)) for (const file of paths) before.set(this.key(file), await this.version(file));
        const result = await client.callTool({ name, arguments: args }, undefined, { timeout: 120000 });
        if (!result.isError) {
          for (const file of readNames.includes(name) ? paths : targets) {
            const version = await this.version(file);
            if (readNames.includes(name) && before.get(this.key(file)) !== version) return failure('FILE_CHANGED_DURING_READ', `The file changed while being read; read it again: ${file}`);
            // read_multiple_files can include per-file errors: recording a version only authorizes a later CAS check, not a blind save.
            task.versions.set(this.key(file), version);
          }
        }
        // UI widgets require resource routing and can issue calls without task_id; return native text/media results.
        const { _meta, ...plain } = result;
        return plain;
      });
    } catch (error) { return failure('LOCAL_TOOL_ERROR', String(error.message || error)); }
    finally { task.pending--; task.lastUsed = Date.now(); }
  }
  async commit(task, args, force) {
    return this.locked([args.source, args.destination], async () => {
      if (this.key(args.source) === this.key(args.destination)) return failure('INVALID_COMMIT', 'Source and destination must differ.');
      const error = await this.checkWrite(task, [args.destination], force); if (error) return error;
      const before = await this.version(args.destination);
      const sourceBefore = await this.version(args.source);
      const temporary = path.join(path.dirname(args.destination), `.${path.basename(args.destination)}.${randomUUID()}.tmp`);
      let backup;
      try {
        await copyFile(args.source, temporary);
        if (await this.version(args.source) !== sourceBefore) return failure('FILE_CONFLICT', 'Working copy changed during commit; retry after it finishes.');
        if (await this.version(args.destination) !== before) return failure('FILE_CONFLICT', 'Destination changed during commit; read latest and merge.');
        if (before !== null) {
          const backups = path.join(this.tasksRoot, task.id, 'backups'); await mkdir(backups, { recursive: true });
          backup = path.join(backups, `${randomUUID()}-${path.basename(args.destination)}`);
          await copyFile(args.destination, backup);
          if (await this.version(args.destination) !== before) return failure('FILE_CONFLICT', 'Destination changed while backing up; read latest and merge.');
        }
        await rename(temporary, args.destination);
        task.versions.set(this.key(args.destination), await this.version(args.destination));
        return ok(`Committed ${args.destination}${backup ? `\nPrevious version backup: ${backup}` : ''}`, { destination: args.destination, ...(backup ? { backup } : {}) });
      } finally { await unlink(temporary).catch(e => { if (e.code !== 'ENOENT') throw e; }); }
    });
  }
  async end(task, force = false) {
    if (task.pending > 1 && !force) return failure('TASK_BUSY', 'Another call in this same task is still running.');
    if (task.client && !force) {
      const sessions = asText(await task.client.callTool({ name: 'list_sessions', arguments: {} }));
      if (sessions !== 'No active sessions') return failure('TASK_BUSY', 'This task has active processes. Finish them, or use force=true to explicitly stop this task.');
    }
    if (force && task.transport?.pid && process.platform === 'win32') {
      const { spawn } = await import('node:child_process');
      await new Promise(resolve => { const p = spawn('taskkill.exe', ['/PID', String(task.transport.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); p.on('close', resolve); p.on('error', resolve); });
    }
    await task.client?.close().catch(() => {});
    this.tasks.delete(task.id);
    return ok('Task closed. Files and backups remain on disk. Other tasks are unaffected.');
  }
  async reap() {
    for (const task of this.tasks.values()) if (!task.internal && task.pending === 0 && Date.now() - task.lastUsed > 24 * 60 * 60 * 1000) await this.end(task, false);
  }
  async close() { for (const task of [...this.tasks.values()]) await this.end(task, true); }
}
