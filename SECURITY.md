# Security and privacy

Full mode authorizes file and command operations as the current Windows user. Restricted mode narrows file-tool directories; its command tools are **not an OS sandbox**. Use a separate Windows account or VM if you need a strict security boundary.

The HTTP gateway binds to loopback. Each person creates their own private tunnel and credential. Credentials are stored with Windows DPAPI and file ACLs in a private runtime outside this repository. Do not publish even encrypted credentials or filled-in connection settings.

File-tool saves check versions. Arbitrary commands and external applications can bypass those checks; work on a copy and use `commit_file` when saving an existing document. Version checks are coordination, not a filesystem sandbox or a universal transaction system.

## Reporting a vulnerability

If GitHub's **Report a vulnerability** option is available under this repository's Security tab, use it for a private report. Otherwise, open an issue containing only a high-level description and a request for a private reporting channel. Do not post an exploit, secret, private file, or identifying runtime log in a public issue.

Include affected versions, the violated boundary, and a minimal reproduction using disposable files. This project does not promise a fixed response time or paid support.
