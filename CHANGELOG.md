# Changelog

## v1.2.1 — 2026-10-11

Sync the current local runtime into the public deployment kit. Runtime diagnostics report `1.2.1-local`; the source kit/package version is `1.2.1`.

- Add background operation IDs, task status, guarded working copies, script execution, request-key idempotency and a ChatGPT return-file interface.
- Keep jobs running after an HTTP response disconnect; reconnect a stopped task backend on the next call.
- Check the tunnel daemon's actual in-memory MCP URL and rebind owned stale processes after gateway port changes.
- Add task-free capabilities, privacy-preserving RPC outcome records and a loopback status dashboard with an optional desktop shortcut.
- Add event-driven supervision and a no-console native guardian built on the receiving Windows computer. No periodic health checks.
- Add portable stability and synthetic artifact-save regressions, preserving pinned dependencies and per-user credentials.
- Preserve scope and connection settings on upgrade; read UTF-8 settings explicitly in Windows PowerShell so non-BOM Chinese paths are retained.
- State limits explicitly: no automatic local binary upload into ChatGPT, no verified real cloud artifact round trip, no task recovery after a gateway restart and no cross-file transaction.
- Keep all private connection identifiers, credentials, user files and runtime reports out of the public repository.

## v1.1.0 — 2026-10-04

First public GitHub release of the Windows setup kit.

- Connect ordinary ChatGPT Chat to local files and commands through OpenAI Secure MCP Tunnel and Desktop Commander.
- Preserve the original 26 tools; add `begin_task`, `end_task`, and `commit_file`.
- Use independent task processes, configuration, work directories, terminal buffers, and search state.
- Detect stale file saves and preserve a backup when committing working copies.
- Return a PID promptly for long commands, so other tasks can proceed.
- Store each user's tunnel credential with Windows DPAPI; keep runtime data outside the public kit.
- Include pinned dependencies, verified tunnel downloads, installation scripts, concurrency checks, and real Chat acceptance checks.
- Publish English and Chinese guides, usage examples, issue templates, and privacy checks.

See [VALIDATION.md](VALIDATION.md) for test scope and remaining limits. Full command access remains available; direct command writes can bypass gateway conflict checks.

## Before the public release

The earlier local deployment used a shared stdio backend. The concurrency findings informed v1.1.0; no private deployment, account identity, credential, or chat history is included here.
