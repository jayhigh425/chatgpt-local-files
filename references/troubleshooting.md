# 只针对实际故障排查

- **Node/npm 不可用**：安装脚本下载官方便携 Node 22 并验证校验值，无需修改系统 PATH。可用 -NodeExecutable 指向已有 Node >=22。网络下载失败时修复接收者代理或网络；不能关闭 TLS 校验。
- **隧道看似正常但 begin_task 失败**：检查 tunnelBindingMatches。connect 可能复用仍指向旧端口的进程；新版启动脚本核对实时管理端点，必要时仅重启本安装的隧道。不要只核对配置文件或 healthy。
- **密钥无法解密**：DPAPI 文件使用当前 Windows 用户加密，只能在同用户/同电脑上下文使用。读取密文先 Trim。换电脑重新创建自己的密钥，不分享密文。
- **密钥过期或未授权**：核实 Tunnels Read/Use、所属组织、自己的 tunnelId 与当前账号；替换运行密钥后重新启动。不要追加模型权限或充值来尝试修复权限错误。
- **ChatGPT 看不到 tunnel**：核实 tunnel 关联了目标 ChatGPT workspace，并核实操作者 Tunnels Use 权限。账号没有自定义 MCP 能力时说明限制，不能声称部署已成功。
- **发现工具失败**：必须有活跃的 tunnel-client；要求 Status 中控制平面轮询也成功。检查是否进程启动、网络、路径和上游 MCP 可用，而不是只看 healthy=true。
- **缺少 begin_task，或提示 TASK_REQUIRED**：刷新插件工具并开启新 Chat；让模型先创建本次任务，再携带其 task_id。服务重启或任务已结束后，旧 task_id 需要重新创建。
- **READ_REQUIRED / FILE_CONFLICT**：先读取当前文件，再基于最新内容合并修改。脚本生成工作副本时，用 commit_file 保存，不能用旧快照无条件覆盖。
- **工具调用失败或超时**：先用 get_operation 按 request_key 查询已提交操作，旧工具可通过 read_file 的 local-assistant://operations/ 虚拟路径查询。诊断摘要在本机状态页；RPC 日志仅记录方法、已知工具名、状态、耗时和随机 trace，不记录参数。不要盲目重复非幂等操作。
- **后台每天停止**：使用 Enable-Autostart.ps1 的事件守护和本机编译的 WinExe 宿主；确认 guardian_running、keeper_running、supervisor_running。人工 Stop 会保留停止标记，不自动抵消用户停止操作。外部网络中断仍会影响远端连接。
- **一个脚本运行很久**：start_process 会先返回 PID，计算继续在任务后台；使用自己的 PID 分次读取结果。不要复用其他任务的进程或搜索编号。
- **ConvertTo-SecureString 模块无法加载**：从 PowerShell 7 启动 Windows PowerShell 时，继承的 PSModulePath 可能选错模块。Common.ps1 已显式加载当前主机 PSHOME 下的 Security 模块；不要删除该步骤。
- **gatewayHealthy=false**：检查本机 Node 网关是否启动、依赖是否安装及 prepare-concurrency.mjs hook 是否就绪。网关只监听 loopback；不要把它改成公网监听来解决本地启动问题。
- **后台网页敏感操作一直加载**：将该标签置于前台再观察真实状态。密钥创建只做一次；先确认是否已生成再重试。
- **现有 Desktop Commander 也发生配置变化**：这是共享用户配置。恢复私有目录 local-settings-backup.json 中的目录与命令设置，或按当前用户决定使用新的范围；不要覆盖整个配置文件。
- **某文件仍拒绝访问**：检查 Windows ACL、文件是否占用、云文件是否下载、本机程序是否安装。Full 只解除工具可配置限制，不等于管理员权限。
- **需要更新**：默认使用本包验证过的固定版本。另查官方发行说明、验证官方 ZIP 新摘要并测试，再改 downloads.json。不要静默替换版本或放弃哈希校验。

停止运行使用 Stop-LocalAssistant.ps1，取消登录自启动使用 Disable-Autostart.ps1。这两项不会删除用户文件、插件或远端 tunnel。完整卸载前先断开自己的 ChatGPT 插件，再自行决定删除私有运行目录和撤销运行密钥。
