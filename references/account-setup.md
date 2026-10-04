# 接收者自己的账号接入

本包是可重复执行的私有部署方案，未包含任何人的现成隧道或插件身份。

1. 在接收者已登录的浏览器打开 [Platform Tunnels](https://platform.openai.com/settings/organization/tunnels)。检查能够创建/管理 tunnel；创建一个属于当前账号的 tunnel，并关联将使用插件的 ChatGPT workspace。个人用户通常使用自己的 personal organization。工作区策略或组织角色缺失时，由该账号的管理员处理。
2. 在 [Runtime API keys](https://platform.openai.com/settings/organization/api-keys) 创建运行密钥，选择自己的项目，Restricted，只勾选 Tunnels Read/Use。创建 tunnel 的管理操作和运行密钥权限是两件事；不要创建管理员密钥给守护进程。选择适合自己的有效期；到期后需换密钥。
3. 运行目录中的 `Set-Connection.ps1 -TunnelId <自己的ID>` 保存非密钥连接标识。不要将这个标识填回公共包。
4. 新建密钥页面只显示一次。用户可以在自己电脑终端运行 `Save-Credential.ps1` 后输入密钥，输入隐藏。另一方式是先在网页复制刚创建的密钥，再在本机运行 `Save-Credential.ps1 -FromClipboard`，脚本检查并加密保存，随后清空剪贴板。仅在明确复制了该密钥时读剪贴板。浏览器自动化也可以在本机内存中提取并转为 SecureString 传给脚本，绝不能把值输出到模型工具结果。
5. 运行 Start-LocalAssistant.ps1，随后 Status-LocalAssistant.ps1。隧道只使用出站 HTTPS；不需要公网端口、ngrok 或收费云机器。
6. 打开 [ChatGPT 插件](https://chatgpt.com/plugins)。添加 → 创建自定义 MCP 服务器；名称“本地电脑助手”，描述可填“在本人 Windows 电脑上处理当前用户可访问的文件，执行本机命令并保存结果”。连接选 Tunnel/隧道，填自己的 tunnelId，认证选 None/无，创建并连接。若入口需要 developer mode，按当前账号允许的设置开启。账号功能、组织权限和界面会变化，应按真实页面核实。
7. 在该插件“管理”中的权限页按当前用户授权选择模式。Full 对应“允许使用所有工具”；Restricted 仍可按用户需求选择审批方式。只更改这个插件。升级已有连接时点击“刷新工具”，在新 Chat 中确认存在 begin_task、end_task、commit_file；v1.1 共 29 个工具。
8. 保持 Windows 已登录、电脑开机联网。执行 New-ChatVerification.ps1，复制它输出的提示到普通 Chat；完成后运行 Confirm-ChatVerification.ps1。它必须显示 verified=true。复杂文档或统计程序需本机已有对应软件。

账号操作遇到“加载中”但无错误时，确认标签页处于前台。登录、真人验证和二次验证让接收者完成。不能将 Share 包内原始资料改成带凭据的已部署插件导出包。

参考：[官方 Secure MCP Tunnel 文档](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)。本流程没有模型 API 调用，也不自动充值；平台收费政策应以运行时官方说明为准。
