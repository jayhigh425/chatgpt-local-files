# Runtime behavior in v1.2.1

The public kit/package version is `1.2.1`. The deployed gateway reports `1.2.1-local`. A plugin's displayed package version is separate from its live MCP runtime; changing a backend does not change the uploaded package's metadata.

## Long operations

Start one `begin_task` for each Chat task. Use its own `task_id` for local calls. `get_capabilities` is available before task creation and reports 36 tools, runtime dependencies and limitations.

Operations that exceed the immediate response window (about 900 ms) return `operation_id` and `operation_state=running`. Query `get_operation` for results. `task_status` lists this task's operations. If the HTTP response is lost, recover a submitted operation with its `request_key`; do not repeat a non-idempotent command blindly.

A request key reused with the same arguments returns the existing operation. Reusing it with different arguments reports `REQUEST_KEY_REUSED`. Tasks have separate request registries. HTTP disconnection does not cancel local work, but gateway termination loses the in-memory registry: this is not restart recovery.

Older conversations can query through `read_file`:

```text
local-assistant://capabilities
local-assistant://task/status
local-assistant://operations/<operation ID>
```

The Desktop Commander backend request deadline is 30 minutes. `run_file_task` starts its own hidden PowerShell/CMD process, keeps stdout/stderr in private task files, and has no automatic execution cutoff. This does not guarantee that a Chat conversation keeps reasoning forever. End a task after its operations and processes finish; explicit cancellation stops only the selected operation's process.

## Editing existing files

`prepare_file_edit` creates working copies and records target versions. Pass its `edit_id` to `run_file_task`; scripts receive working-copy locations through `LOCAL_ASSISTANT_WORK_FILES`. Use `publish=true` or `commit_file_edit` to publish after checks. A stale target reports `FILE_CONFLICT` and keeps the working copy for reconciliation.

The older `commit_file` remains available for a single working copy and preserves a backup of the previous target. Arbitrary commands keep their authorized filesystem access and can bypass file checks. Multiple files are replaced individually; the set is not an atomic transaction with rollback.

## Connection supervision and status

`Enable-Autostart.ps1` uses a current-user scheduled task with login/resume triggers, no execution-duration limit and restart on failure. The native WinExe guardian is compiled locally from `KeeperHost.cs`; it starts hidden PowerShell workers and waits on process exits. There is no repeating health-check timer. Retry delays apply after failures.

Startup checks the owned tunnel daemon's live `/api/status` target against the running gateway URL. A reused daemon can still forward to a prior ephemeral port even though its saved profile and health look correct. The startup script stops and reconnects this installation's owned stale tunnel, retaining an already healthy gateway and its tasks.

Use `Status-LocalAssistant.ps1` to verify:

```text
process_running, healthy, ready, controlPlanePoll,
gatewayHealthy, tunnelBindingMatches
```

Autostart also exposes `guardian_running`, `keeper_running` and `supervisor_running`. A manual `Stop-LocalAssistant.ps1` leaves a stop marker; supervision does not undo that choice. Start explicitly to resume. Network outages, suspended/offline computers, revoked credentials and unavailable platform features can still prevent remote calls.

`Open-Status.ps1` discovers the current loopback port. `Install-StatusShortcut.ps1` creates a desktop entry and generates its icon on the receiving computer. The dashboard refreshes connection health on demand and receives task updates through SSE. RPC diagnostic records contain random trace IDs, times, known method/tool names, status and duration; they exclude tool arguments, command text, file contents and signed download URLs. All runtime records remain private.

## File transfer and visual checks

| Direction | Status |
| --- | --- |
| Local content to the Chat conversation | Available through local read tools. |
| Local Word/Excel/PDF binary into ChatGPT's file/code environment | Automatic transfer is not implemented. Upload manually when the cloud environment needs the original artifact. |
| ChatGPT file object to the local computer | `save_chatgpt_file` accepts the host-provided `download_url` and `file_id`, streams HTTPS bytes and checks destination conflicts. Synthetic download/error tests pass; a real cloud-generated binary round trip has not been verified. |

Word/Excel/PDF visual quality checks should use ChatGPT's own file/code environment. Generate/render/view there, fix layout there, and report which pages/sheets were actually inspected. The gateway does not render documents locally, perform local OCR or certify a self-reported `qa_report`. A successful text read or download is not proof of visual inspection. If that cloud environment or a usable file object is unavailable, state the incomplete step.

## Local regressions

Run against your own installed private directory:

```powershell
node .\scripts\Test-Concurrency.mjs "$env:LOCALAPPDATA\ChatGPTLocalAssistant"
node .\scripts\Test-Stability.mjs "$env:LOCALAPPDATA\ChatGPTLocalAssistant" --short
node .\scripts\Test-CloudFile.mjs "$env:LOCALAPPDATA\ChatGPTLocalAssistant"
```

The stability test creates a separate loopback gateway and disposable fixtures under the private runtime's `verification` directory. It does not start a tunnel or call model APIs. Without `--short`, it runs a 130-second sleep fixture to test operation lifecycle across the old response deadline; it is not a realistic lengthy computation or proof of indefinite uptime. The cloud-file test mocks the HTTPS response and explicitly does not verify ChatGPT rendering or real cloud file access.

The concurrency test uses the already selected file scope. Stability and synthetic file tests use a separate Full test configuration and operate on their own fixtures; the live installation's scope is not changed. Generated reports stay private and must not be added to this repository.

The SDK is pinned to `1.32.0` and its supported protocol `2025-11-25`. Newer JSON-RPC tool callers have limited compatibility; this kit does not claim a full MCP 2026 implementation.
