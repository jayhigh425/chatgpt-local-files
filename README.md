# ChatGPT Local Files

**Let ordinary ChatGPT Chat read, edit, run commands, and save files on your own Windows computer.**

[![MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/platform-Windows_10%2F11-blue.svg)](docs/SETUP.en.md)
[![Release](https://img.shields.io/github/v/release/jayhigh425/chatgpt-local-files)](https://github.com/jayhigh425/chatgpt-local-files/releases/latest)
[![Public kit checks](https://github.com/jayhigh425/chatgpt-local-files/actions/workflows/validate.yml/badge.svg)](https://github.com/jayhigh425/chatgpt-local-files/actions/workflows/validate.yml)

**English** · [简体中文](README.zh-CN.md) · [Download](https://github.com/jayhigh425/chatgpt-local-files/releases/latest) · [Examples](docs/EXAMPLES.md) · [Setup guide](docs/SETUP.en.md)

![ChatGPT Local Files: your ChatGPT chat, your Windows files](docs/banner.svg)

Ask ChatGPT to find research notes, edit a local document, run an installed script, or save a result to your disk. This open-source setup kit connects ChatGPT Chat to [Desktop Commander](https://github.com/wonderwhy-er/DesktopCommanderMCP) through [OpenAI Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), with a local task gateway for concurrent work.

**Inference stays in your ChatGPT Chat session. The kit makes no model API calls and does not ask you to recharge API credits.** A tunnel-only runtime credential is required. Your account must expose the required tunnel and custom MCP/plugin features; availability and future platform pricing are outside this project's control.

## What you can do

| Capability | How it works |
| --- | --- |
| Read and search local files | Operate on your own Windows filesystem instead of uploading every working file manually. |
| Edit and save results | Changes and generated outputs are saved directly on your computer. |
| Run local programs | Use installed command-line tools as the current Windows user. |
| Work across several chats | Separate task processes, configurations, terminal buffers, search state, and working directories. |
| Handle competing file edits | Detect stale saves; reread and merge. Commit working copies with a backup of the previous target. |
| Configure another computer | Give the public kit to that person's Codex. Each user creates their own private connection. |

Full mode supports the current user's accessible filesystem and commands, including an entire drive. It does not grant administrator privileges. Restricted mode narrows file-tool paths; command tools are not an OS sandbox. See [security boundaries](SECURITY.md).

## Quick start

1. [Download the latest release](https://github.com/jayhigh425/chatgpt-local-files/releases/latest), extract the complete ZIP, and keep its folder structure.
2. Give the extracted directory to **your own Codex**, together with this prompt:

```text
Read this kit's AGENTS.md, SKILL.md, README.md, and docs/SETUP.en.md.
Configure Local Computer Assistant on my Windows computer so ordinary
ChatGPT Chat can read, edit, and save local files and run local commands.
I authorize access to all files and commands available to my current
Windows user, and Allow all tools for this plugin. Use my own account
and private tunnel. Use ChatGPT Chat for inference; do not call model
APIs, recharge API credit, or buy third-party services. I authorize
hidden background startup at login. Keep credentials out of chat,
logs, and shareable files. Verify actual ordinary Chat read/write/edit
behavior and local output before reporting setup complete.
```

3. Complete login or human verification yourself when needed. After configuration, use a **new ordinary Chat** with your own plugin enabled.

Prefer a narrower file scope? Replace the full-access sentence with your chosen folders and request Restricted mode. Each person's authorization and credentials belong to them.

### Manual local install

Windows 10/11 x64, internet, and access to the required account features are prerequisites. Run from the kit root after authorizing your chosen scope:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-LocalAssistant.ps1 -AccessMode Full
```

This installs local tools. Continue with the [account connection and real Chat verification](docs/SETUP.en.md); local installation alone is not a completed ChatGPT connection.

The default installed runtime is `%LOCALAPPDATA%\ChatGPTLocalAssistant`. Keep it private. Share this repository or release ZIP, never the installed runtime.

## Try it in Chat

After setup, select your Local Computer Assistant plugin and try:

> Search D:\Research for relevant notes, summarize them with local filenames, and save the result as D:\Research\summary.md.

> Read D:\Projects\notes.md, improve the wording, preserve headings, and save it. If the file changed, reread and merge. Verify the saved content.

> Run my installed script on disposable input. Return its PID, poll progress, and put outputs in the task work directory. Use commit_file when writing a working copy back to an existing file.

More [English and Chinese examples](docs/EXAMPLES.md).

## How it works

```mermaid
flowchart LR
    Chat[Ordinary ChatGPT Chat] --> Tunnel[Your private Secure MCP Tunnel]
    Tunnel --> Gateway[Loopback HTTP task gateway]
    Gateway --> A[Task A: independent Desktop Commander]
    Gateway --> B[Task B: independent Desktop Commander]
    A --> Files[Your Windows files and programs]
    B --> Files
```

The original 26 Desktop Commander tools remain, with three additional tools:

| Tool | Purpose |
| --- | --- |
| `begin_task` | Create this chat's task ID, isolated backend, and working directory. |
| `end_task` | Close the task when its work and processes finish; retain files. |
| `commit_file` | Save a working copy after a version check, preserving a backup of the previous target. |

Subsequent tool calls carry that task's `task_id`. Long commands return a PID promptly, so another task can continue. File tools coordinate saves and report `READ_REQUIRED` or `FILE_CONFLICT` when appropriate. Direct command writes can bypass these checks; use working copies and coordinate final writes to the same file.

## FAQ

**Does this spend model API credit?** The kit does not call model APIs. ChatGPT Chat supplies inference. You still create a runtime credential with Tunnels Read/Use only. The kit does not purchase services or guarantee future OpenAI pricing.

**Does it work on every ChatGPT account?** No. Required tunnel and custom MCP/plugin features must be available to the account and workspace. Check the live official interface before assuming eligibility.

**Can it replace every Codex or Work feature?** It provides local file and command tools to ordinary Chat. It does not reproduce the full Codex/Work product, give administrator rights, or provide complete screen control.

**Are my files entirely processed offline?** No. Tool results are supplied to ChatGPT in the cloud. The gateway is local, but the chat and private tunnel require internet. Choose the files you ask Chat to process accordingly.

**Can I share my configured plugin?** Share the public kit. Others create their own tunnel, credential, and private plugin. This is not a shared remote computer or a public plugin-store listing.

**What has been tested?** Windows PowerShell 5.1 installation, Chinese/space paths, pinned dependencies, scope configuration, file operations, process isolation, concurrent edit conflict handling, actual tunnel HTTP forwarding with a local mock control plane, and one real ordinary Chat acceptance run. New users must pass their own acceptance test. See [VALIDATION.md](VALIDATION.md).

## Project files

- [SKILL.md](SKILL.md): deployment instructions for Codex.
- [English setup](docs/SETUP.en.md), [Chinese account setup](references/account-setup.md), [troubleshooting](references/troubleshooting.md).
- `runtime/`: task gateway, credentials, startup, health, stopping, and Chat verification.
- `scripts/`: installation, concurrency verification, and public-package privacy checks.
- `assets/`: pinned dependency lockfile and official download hashes.
- [PRIVACY-AUDIT.md](PRIVACY-AUDIT.md), [SHA256SUMS.txt](SHA256SUMS.txt): public package checks and integrity manifest.
- [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md).

## Help the project improve

If it works for you, a star or a link to your verified workflow helps others find it. Report redacted setup problems, improve the guides, or contribute a reproducible fix. Never upload credentials, private account identifiers, logs containing personal data, or user documents to issues.

Built on [Desktop Commander](https://github.com/wonderwhy-er/DesktopCommanderMCP), [OpenAI tunnel-client](https://github.com/openai/tunnel-client), and the [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk). This independent community project is not an official OpenAI product. Original kit code and guides are [MIT licensed](LICENSE); upstream dependencies retain their licenses.