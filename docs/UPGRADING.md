# Upgrade an existing private installation / 升级已有安装

Use the [current source ZIP](https://github.com/jayhigh425/chatgpt-local-files/archive/refs/heads/main.zip). Extract it outside your existing private runtime. The public kit is not a personal ChatGPT plugin-upload ZIP and does not contain anyone's app/tunnel identity.

1. Finish active tasks and save their outputs. Record your runtime directory, authorized access mode and whether autostart was enabled. Keep an optional local backup private.
2. In the **old private runtime**, run `Stop-LocalAssistant.ps1` and `Disable-Autostart.ps1`. Verify its gateway and guardian have exited. Stopping ends active tool processes; gateway tasks are not recovered after restart.
3. From the new kit, run the installer with your existing runtime directory. It preserves the connection identifier, credentials and access mode when scope parameters are omitted. A configured `ConfigHome` is also retained. Explicit scope parameters override those saved values.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check-ShareSafety.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-LocalAssistant.ps1 -RuntimeDirectory "$env:LOCALAPPDATA\ChatGPTLocalAssistant"
```

4. Run the upgraded runtime's `Start-LocalAssistant.ps1` and `Status-LocalAssistant.ps1`. Require the six connection fields in [RUNTIME.md](RUNTIME.md), including `tunnelBindingMatches`. If desired and already authorized, run `Enable-Autostart.ps1` again. `Install-StatusShortcut.ps1` is optional.
5. Refresh your **existing private plugin** in ChatGPT. Verify 36 tools and `get_capabilities`, open a new ordinary Chat and rerun the Chat verification scripts. Do not create another tunnel or credential merely because the runtime was updated.

The runtime reports `1.2.1-local`; the source/package version is `1.2.1`. A ChatGPT plugin listing may retain older package metadata until that user's own package is updated. Never upload the maintainer's personal plugin ZIP or reuse another user's connection identifiers.

中文版要点：先结束任务，在旧运行目录停止助手并禁用守护，然后把新公开包安装到同一个私有运行目录，保留自己的凭据和权限。启动后检查实时隧道绑定，恢复已授权的自启动，在原插件刷新 36 个工具并新建 Chat 验收。公开源码 ZIP 用于本机部署，不直接作为含个人连接的插件 ZIP 上传。
