# Windows setup guide

This kit connects **ordinary ChatGPT Chat** to the current user's Windows computer through a private OpenAI Secure MCP Tunnel. It runs local tools; it does not call a model API. Each user needs their own account, tunnel, connection, and credential.

## Prerequisites

- Windows 10/11 x64 and internet access.
- An account that actually exposes the required tunnel and custom MCP/plugin features. Account policies and availability may differ; check the live official interface.
- The current user's authorization for the requested file and command scope.
- Node >=22, or permission for the installer to download a verified portable Node 22 runtime.

The installer does not buy services, recharge API credits, elevate Windows privileges, or disable system security. A runtime key with **Tunnels Read/Use only** is still required; it is not a model API key for inference. Future platform pricing is outside the kit's control.

## Recommended: ask Codex to configure it

Download and extract the release ZIP. Give your own Codex the extracted folder and the prompt in the English README. Codex should read `AGENTS.md`, `SKILL.md`, and this guide, complete setup, and independently verify actual ordinary Chat read/write behavior.

You must complete login, CAPTCHA, MFA, or hardware verification yourself. Do not put a key, password, or verification code into the chat.

## 1. Install the local tools

From the kit root, after authorizing full access:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check-ShareSafety.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-LocalAssistant.ps1 -AccessMode Full
```

For a chosen file-tool scope:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-LocalAssistant.ps1 -AccessMode Restricted -AllowedDirectories 'D:\Research'
```

Restricted narrows file tools. Command tools still run as the current Windows user; it is not an OS sandbox.

The default private runtime is `%LOCALAPPDATA%\ChatGPTLocalAssistant`. The kit stays public and unfilled. Never upload or redistribute the installed runtime. Installation backs up relevant existing Desktop Commander user configuration before changing it; the shared base configuration may affect other Desktop Commander clients.

Pinned dependencies and tunnel download hashes are in `assets/`. The installer adds a tested per-task configuration hook without changing the Windows user profile. Do not remove the hook or return to a shared stdio backend.

## 2. Create your own connection

Follow the current [official tunnel documentation](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), checking the actual account interface.

1. Open [Platform Tunnels](https://platform.openai.com/settings/organization/tunnels). Create your own tunnel and link it to the ChatGPT workspace that will use the plugin. Missing organization roles or workspace policy permissions must be resolved by that account's administrator.
2. Open [runtime API keys](https://platform.openai.com/settings/organization/api-keys). Create a restricted runtime key for your own project with **Tunnels Read/Use** only. The daemon does not need an admin key or model permissions. Manage expiry yourself.
3. In the private runtime, use `Set-Connection.ps1 -TunnelId <your own tunnel ID>` to store your own connection identifier. Do not fill it into this repository.
4. Save the key using `Save-Credential.ps1` in a local terminal with hidden input. Alternatively, copy the freshly created key yourself and use `Save-Credential.ps1 -FromClipboard`; it encrypts the value and clears the clipboard. Only read the clipboard when the user has explicitly copied that key. Never print the value, capture it in model-visible browser output, or write it to a log.

The script uses DPAPI for the current Windows user and restricts credential file access. Copying encrypted credentials to another computer is not a deployment method; create a fresh connection there.

## 3. Start and check health

Run `Start-LocalAssistant.ps1` and then `Status-LocalAssistant.ps1` from the private runtime. Require all five fields:

```text
process_running = true
healthy = true
ready = true
controlPlanePoll = true
gatewayHealthy = true
```

The gateway listens only on loopback and the tunnel connects through outbound HTTPS. No public local port, third-party forwarding service, or paid cloud host is required by this setup.

## 4. Connect ordinary ChatGPT Chat

Open [ChatGPT plugins](https://chatgpt.com/plugins). Add a custom MCP server using **Tunnel**, enter your own tunnel ID, and choose **None** for the MCP authentication option. Name it `Local Computer Assistant` or `本地电脑助手`. Enable developer mode only if the account's current interface requires and allows it.

Connect the plugin. If the user authorized Full mode, choose **Allow all tools** for this plugin. Do not change unrelated plugins. Refresh its tools and confirm **29 tools**, including `begin_task`, `end_task`, and `commit_file`. Use a new ordinary Chat; previous conversations may cache old tools.

## 5. Verify real Chat behavior

Run `New-ChatVerification.ps1` from the private runtime, paste its prompt into ordinary Chat, and let Chat complete it. Chat must create its own task, read the random fixture, write its calculated result locally, edit an existing text file, reread, and end its task.

Run `Confirm-ChatVerification.ps1` locally and require `verified=true`. Codex must not produce the expected output on Chat's behalf. A successful local install or healthy process alone does not prove the account-to-Chat connection.

Optional concurrency verification:

```powershell
node .\scripts\Test-Concurrency.mjs "$env:LOCALAPPDATA\ChatGPTLocalAssistant"
```

This uses disposable fixtures and the already selected scope. Its report stays in the private runtime.

## 6. Startup and stopping

If the user authorizes login startup, run `Enable-Autostart.ps1`. The current user's Startup shortcut launches hidden background processes. The computer must stay on, signed in, and online for remote tool calls.

Use `Stop-LocalAssistant.ps1` to stop the tunnel and task gateway; active tool processes are stopped with the gateway. Use `Disable-Autostart.ps1` to remove this shortcut. These actions preserve saved files and do not delete the remote tunnel or plugin.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Missing tools or `TASK_REQUIRED` | Refresh tools, start a new Chat, call `begin_task`, and pass the returned task ID. IDs expire after end/restart. |
| `READ_REQUIRED` | Read the existing target before writing. |
| `FILE_CONFLICT` | Reread current contents, merge, and retry; do not silently discard newer edits. |
| Long-running command | Poll the returned PID using that task's tools. |
| `gatewayHealthy=false` | Node process, installed dependencies, gateway logs, and the configuration hook. Keep the bind address on loopback. |
| Tunnel healthy but tools unavailable | Require successful control-plane polling; check your workspace link, account features, and Tunnels Use permission. |
| Key cannot decrypt | Use the original Windows user context; on a new computer create and save a fresh key. |
| Key expired/unauthorized | Check expiry, your own tunnel and organization, and Tunnels Read/Use. Adding model permissions or API credit is not this kit's fix. |
| PowerShell security module fails | Preserve the explicit current-PSHOME module import in `Common.ps1`. |
| Access denied in Full mode | Windows file ACLs, file locks, cloud file availability, and installed local applications still apply. |

See [validation scope](../VALIDATION.md), [privacy audit](../PRIVACY-AUDIT.md), and the [Chinese troubleshooting guide](../references/troubleshooting.md).
