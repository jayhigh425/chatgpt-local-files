---
name: chatgpt-local-assistant-setup
description: 在 Windows x64 上配置普通 ChatGPT Chat 的私有本地文件与命令助手，使用 Desktop Commander 和 OpenAI Secure MCP Tunnel。适用于安装、迁移和验收这个部署包；不用于发布公共插件或替代 Codex 自身文件工具。
---

部署目标是普通 ChatGPT Chat 调用接收者本机工具，结果直接保存到本机。权限、凭据和路径必须来自当前接收者。

## 部署顺序

1. 读取本包 AGENTS.md；确认 Windows x64、账号入口和用户授权范围。查阅官方文档，处理与包内已验证界面有差异的现行入口。
2. 运行 `scripts/Check-ShareSafety.ps1`，再运行 `scripts/Install-LocalAssistant.ps1 -AccessMode Full`，或者按用户目录使用 Restricted。默认安装目录自动取当前用户 LOCALAPPDATA。脚本自动检测 Node.js，必要时从官方源下载便携 Node 22；使用固定 lockfile 安装开源依赖，校验官方隧道发行 ZIP 的 SHA256。不要复制本包到已有私有运行目录后再分享。
3. 按 [账号接入说明](references/account-setup.md) 创建/复用当前接收者自己的 tunnel，并关联目标 ChatGPT workspace。运行密钥仅开放 Tunnels Read/Use。用运行目录的 Set-Connection.ps1 保存接收者 tunnelId，Save-Credential.ps1 安全保存密钥。
4. 运行私有目录 Start-LocalAssistant.ps1。脚本启动仅监听 loopback 的 HTTP 任务网关，并将管理式隧道连接到该网关；不要换回共享 stdio 命令。查看 Status-LocalAssistant.ps1，要求 process_running、healthy、ready、controlPlanePoll、gatewayHealthy 均为 true。每个任务的配置目录通过已校验的 Desktop Commander 配置 hook 指定，不改 Windows 用户 profile。
5. 保持隧道运行。在 ChatGPT 插件页面创建自定义 MCP，名为“本地电脑助手”，选择“隧道”，填接收者自己的 tunnelId，身份验证选“无”，连接插件。用户授权 Full 时，仅把这个插件的权限设为“允许使用所有工具”；不改变其他插件的权限。
6. 创建或升级插件后，在设置刷新操作，确认共 29 个工具并出现 begin_task；旧 Chat 可能缓存工具，使用新 Chat。用 New-ChatVerification.ps1 生成验收提示，保持“聊天”模式，将提示发送给普通 Chat。确认它创建自己的 task_id、读写修改并 end_task。随后运行 Confirm-ChatVerification.ps1 独立校验本机输出中的随机标识、计算结果与修改状态。不能把写入测试结果的步骤改由 Codex 代做来冒充 Chat 成功。
7. 用户授权自启动时，运行 Enable-Autostart.ps1。交付名称、运行目录、权限模式、停止方式、验收状态与任何未完成条件。不要在交付消息展示凭据。

遇到下载、路径、凭据、权限或发现失败，按 [排障说明](references/troubleshooting.md) 定位。脚本不证明新账号具有平台功能；新电脑必须独立完成账号和 Chat 验收。
