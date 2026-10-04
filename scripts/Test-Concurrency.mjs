import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';
const root = process.argv[2];
if (!root) throw new Error('Pass your own installed private runtime directory as the first argument.');
const { TaskGateway } = await import(pathToFileURL(path.join(root, 'task-gateway-core.mjs')));
const settings = JSON.parse((await readFile(path.join(root, 'settings.private.json'), 'utf8')).replace(/^\uFEFF/, ''));
const gateway = new TaskGateway(root, settings);
const report = { tests: {}, startedAt: new Date().toISOString() };
const text = r => JSON.stringify(r);
const assert = (value, label) => { if (!value) throw new Error(label); };
let a, b;
try {
  await gateway.init();
  a = (await gateway.call('begin_task', { label: 'Isolated test A' })).structuredContent;
  b = (await gateway.call('begin_task', { label: 'Isolated test B' })).structuredContent;
  const call = (task, name, args) => gateway.call(name, { task_id: task.task_id, ...args });
  const shared = path.join(a.work_directory, 'shared.txt');
  await writeFile(shared, 'A=original\nB=original\n');
  await call(a, 'read_file', { path: shared }); await call(b, 'read_file', { path: shared });
  const edits = await Promise.all([
    call(a, 'edit_block', { file_path: shared, old_string: 'A=original', new_string: 'A=changed' }),
    call(b, 'edit_block', { file_path: shared, old_string: 'B=original', new_string: 'B=changed' })
  ]);
  assert(edits.filter(x => !x.isError).length === 1 && edits.some(x => text(x).includes('FILE_CONFLICT')), 'Concurrent file edits must report one conflict');
  const loser = edits[0].isError ? a : b;
  const key = edits[0].isError ? 'A' : 'B';
  await call(loser, 'read_file', { path: shared });
  assert(!(await call(loser, 'edit_block', { file_path: shared, old_string: `${key}=original`, new_string: `${key}=changed` })).isError, 'Retry edit after refresh');
  const combined = await readFile(shared, 'utf8'); assert(combined.includes('A=changed') && combined.includes('B=changed'), 'Both changes preserved after merge');
  report.tests.concurrentEdits = { conflictReported: true, bothChangesPreservedAfterRefresh: true };

  await writeFile(shared, 'A=original\nB=original\n');
  await call(a, 'read_file', { path: shared }); await call(b, 'read_file', { path: shared });
  assert(!(await call(a, 'write_file', { path: shared, content: 'A=changed\nB=original\n', mode: 'rewrite' })).isError, 'First save');
  const stale = await call(b, 'write_file', { path: shared, content: 'A=original\nB=changed\n', mode: 'rewrite' });
  assert(stale.isError && text(stale).includes('FILE_CONFLICT'), 'Stale snapshot overwrite rejected');
  assert((await readFile(shared, 'utf8')).includes('A=changed'), 'Earlier save preserved');
  report.tests.staleSave = { conflictDetected: true, firstSavePreserved: true };
  await call(a, 'read_file', { path: shared }); await writeFile(shared, 'external-change\n');
  assert(text(await call(a, 'write_file', { path: shared, content: 'old', mode: 'rewrite' })).includes('FILE_CONFLICT'), 'External save detected');
  report.tests.externalSave = { conflictDetected: true };
  const newFile = path.join(b.work_directory, 'copy.txt'); await writeFile(newFile, 'merged-output\n');
  await call(b, 'read_file', { path: shared });
  const commit = await call(b, 'commit_file', { source: newFile, destination: shared });
  assert(!commit.isError && commit.structuredContent.backup, 'CAS commit with backup');
  assert(await readFile(commit.structuredContent.backup, 'utf8') === 'external-change\n', 'Backup correct');
  report.tests.commit = { succeeded: true, previousVersionBackedUp: true };

  const configA = gateway.tasks.get(a.task_id).configDir, configB = gateway.tasks.get(b.task_id).configDir;
  assert(configA !== configB, 'Task configuration directories differ');
  const initialB = JSON.parse(await readFile(path.join(configB, 'config.json'), 'utf8'));
  const newLimit = Number(initialB.fileReadLineLimit || 1000) + 1;
  await call(a, 'set_config_value', { key: 'fileReadLineLimit', value: newLimit });
  const readA = JSON.parse(await readFile(path.join(configA, 'config.json'), 'utf8'));
  const readB = JSON.parse(await readFile(path.join(configB, 'config.json'), 'utf8'));
  assert(readA.fileReadLineLimit === newLimit && readB.fileReadLineLimit !== newLimit, 'Config mutation not shared');
  report.tests.config = { isolated: true, modificationsDoNotLeak: true };

  const processStart = await call(a, 'start_process', { command: "Start-Sleep -Seconds 8; Write-Output 'TASK_A_DONE'", timeout_ms: 30000 });
  const pid = Number(text(processStart).match(/PID (\d+)/)?.[1]); assert(pid > 0, 'Test PID');
  const started = Date.now(); const quick = await call(b, 'read_file', { path: shared }); const quickMs = Date.now() - started;
  assert(!quick.isError && quickMs < 1500, 'Slow A process should not delay B read');
  assert(text(await call(a, 'list_sessions', {})).includes(String(pid)), 'Task A sees its process');
  assert(!text(await call(b, 'list_sessions', {})).includes(String(pid)), 'Task B does not see A process');
  assert((await call(b, 'read_process_output', { pid, timeout_ms: 1 })).isError, 'Task B cannot accidentally consume A process buffer');
  report.tests.processIsolation = { quickReadMs: quickMs, separateSessions: true, buffersIsolated: true };
  assert(text(await gateway.call('end_task', { task_id: a.task_id })).includes('TASK_BUSY'), 'End cannot silently stop a running process');
  await call(a, 'force_terminate', { pid });
  const files = Array.from({ length: 16 }, (_, i) => path.join(a.work_directory, `file-${i}.txt`));
  await Promise.all(files.map((f, i) => writeFile(f, `UNIQUE_${i}\n`)));
  const reads = await Promise.all(files.map((f, i) => call(i % 2 ? a : b, 'read_file', { path: f }).then(r => text(r).includes(`UNIQUE_${i}`))));
  assert(reads.every(Boolean), 'Concurrent reads correct'); report.tests.parallelReads = { correct: reads.filter(Boolean).length, total: reads.length };
  assert(text(await gateway.call('write_file', { path: shared, content: 'no task' })).includes('TASK_REQUIRED'), 'Missing task is recoverable error');
  report.tests.taskRequirement = { enforced: true };
  report.passed = true;
} catch (e) { report.passed = false; report.error = String(e); process.exitCode = 1; }
finally { await gateway.close(); await writeFile(path.join(root, 'concurrency-verification.private.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report)); }
