# Contributing

Help other people get a verified ordinary ChatGPT Chat connection on their own Windows computer.

- Report setup failures with the Windows, Node, and kit versions, the failing step, and a **redacted** error. Remove credentials, account/tunnel/workspace IDs, chat URLs, user paths, and file contents.
- Suggest improvements through an issue. A useful first contribution is an English/Chinese documentation correction, a reproducible network or path fix, or a stronger concurrency check.
- For code changes, keep pinned dependencies, loopback-only gateway binding, per-task configuration, task IDs, file version checks, and secret handling intact.
- Run `scripts/Check-ShareSafety.ps1`, syntax checks, and relevant verification. Changes to runtime behavior need `scripts/Test-Concurrency.mjs` on an isolated private runtime; account integration changes need an actual ordinary Chat acceptance test.
- Regenerate `SHA256SUMS.txt` after changing public files. Do not commit a private runtime, installer output, `node_modules`, or credentials.

This project welcomes reproducible bug reports and improvements. Stars and sharing are useful when the kit solves a real problem for you.

Dependency licenses stay with their upstream projects. Security reports should follow [SECURITY.md](SECURITY.md).
