const $ = id => document.getElementById(id);
const token = document.querySelector('meta[name="assistant-instance"]').content;
const node = (tag, value, className) => { const element = document.createElement(tag); if (value !== undefined) element.textContent = value; if (className) element.className = className; return element; };
const states = { running: '运行中', completed: '已完成', failed: '失败 / 已停止' };
const time = value => new Date(value).toLocaleTimeString('zh-CN', { hour12: false });
async function action(input) {
  const response = await fetch('/api/action', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Local-Assistant-Instance': token }, body: JSON.stringify(input) });
  const result = await response.json(); if (!response.ok) throw new Error(result.error || result.content?.[0]?.text || '操作失败');
  $('notice').textContent = '操作已提交。';
}
function button(label, handler, danger = false) {
  const element = node('button', label, danger ? 'danger' : '');
  element.onclick = async () => { element.disabled = true; try { await handler(); } catch (error) { $('notice').textContent = error.message; } finally { element.disabled = false; } }; return element;
}
function render(data) {
  $('version').textContent = `本机版本 ${data.version} · ${data.tool_count} 个本机工具`;
  $('task-count').textContent = data.tasks.length;
  $('running-count').textContent = data.operations.filter(op => op.state === 'running').length;
  $('uptime').textContent = data.uptime_seconds < 3600 ? `${Math.floor(data.uptime_seconds / 60)} 分` : `${(data.uptime_seconds / 3600).toFixed(1)} 时`;
  if (data.connection) {
    const labels = { process_running: '隧道进程', healthy: '隧道健康', ready: '隧道就绪', controlPlanePoll: '云端连接', gatewayHealthy: '本地网关', tunnelBindingMatches: '隧道连接当前网关', supervisor_running: '内层守护', keeper_running: '外层守护', guardian_running: '无控制台后台宿主', autostart: '登录自动启动' };
    $('connection').replaceChildren();
    for (const [key, label] of Object.entries(labels)) $('connection').append(node('span', label), node('span', data.connection[key] === true ? '正常' : data.connection[key] === false ? '未运行' : '未知', data.connection[key] ? 'live' : 'off'));
  }
  $('tasks').replaceChildren(); $('tasks-empty').hidden = data.tasks.length > 0;
  for (const task of data.tasks) {
    const row = node('tr'), name = node('td'), directory = node('td'), controls = node('td');
    name.append(node('div', task.label), node('code', task.task_id)); directory.append(node('code', task.work_directory, 'path'));
    controls.append(button(task.pending ? '停止此任务' : '关闭任务', async () => {
      if (task.pending && !confirm('停止此任务的进程和操作？工作文件会保留。')) return;
      try { await action({ action: 'end_task', task_id: task.task_id, force: task.pending > 0 }); }
      catch (error) { if (String(error.message).includes('TASK_BUSY') && confirm('此任务仍有本地进程。停止它们并关闭任务？')) await action({ action: 'end_task', task_id: task.task_id, force: true }); else throw error; }
    }, true)); row.append(name, directory, controls); $('tasks').append(row);
  }
  $('operations').replaceChildren(); $('operations-empty').hidden = data.operations.length > 0;
  for (const op of data.operations.slice().reverse()) {
    const row = node('tr'), name = node('td'), state = node('td', states[op.state] || op.state), date = node('td', time(op.started_at)), controls = node('td');
    name.append(node('div', op.tool), node('code', op.operation_id)); if (op.code) state.append(node('div', op.code, 'off'));
    if (op.state === 'running') controls.append(button('停止', async () => { if (confirm('停止这个后台操作？已经完成的文件修改不会撤销。')) await action({ action: 'stop_operation', operation_id: op.operation_id }); }, true));
    row.append(name, state, date, controls); $('operations').append(row);
  }
  $('events').replaceChildren();
  if (!data.events.length) $('events').textContent = '暂无事件。';
  for (const event of data.events.slice().reverse()) { const row = node('div', undefined, 'event'); row.append(node('time', time(event.at)), node('span', `${event.tool} · ${states[event.state] || event.kind}${event.code ? ` · ${event.code}` : ''}`)); $('events').append(row); }
  $('rpc').replaceChildren();
  if (!data.diagnostics?.recent.length) $('rpc').textContent = '暂无到达当前网关的调用。隧道在线不代表工具调用成功；点击刷新检查实际绑定。';
  for (const event of (data.diagnostics?.recent || []).slice().reverse()) {
    const row = node('div', undefined, 'event'); row.append(node('time', time(event.at)), node('span', `${event.tool || event.method} · ${event.outcome} · HTTP ${event.http_status} · ${event.duration_ms} ms${event.code ? ` · ${event.code}` : ''}`), node('code', event.trace_id)); $('rpc').append(row);
  }
}
async function refresh() {
  $('refresh').disabled = true; $('notice').textContent = '正在检查连接…';
  try { const response = await fetch('/api/connection'); const data = await response.json(); if (!response.ok) throw new Error(data.error); render(data); $('notice').textContent = data.connection?.tunnelBindingMatches ? '本机连接和实际网关绑定已确认。ChatGPT 调用请看下方记录。' : '隧道未确认连接到当前网关。点击“恢复连接 / 守护”修复。'; }
  catch (error) { $('notice').textContent = `连接检查失败：${error.message}`; }
  finally { $('refresh').disabled = false; }
}
$('refresh').onclick = refresh;
$('restore').onclick = () => action({ action: 'restore_connection' }).catch(error => { $('notice').textContent = error.message; });
$('stop').onclick = () => { if (confirm('停止本地连接和当前任务？再次使用时可双击状态页启动器恢复。')) action({ action: 'stop_connection' }).catch(error => { $('notice').textContent = error.message; }); };
const events = new EventSource('/events');
events.onopen = () => { $('live').textContent = '状态推送已连接'; $('live').className = 'pill live'; };
events.onmessage = event => render(JSON.parse(event.data));
events.onerror = () => { $('live').textContent = '连接已断开，正在重连'; $('live').className = 'pill off'; };
refresh();
