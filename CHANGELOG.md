# Changelog

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
