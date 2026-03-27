# Security Policy

## Supported Versions

Only the latest release of WiredSwift receives security fixes.

| Version | Supported |
|---------|-----------|
| 3.0.x   | ✅        |
| < 3.0   | ❌        |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please use [GitHub Private Vulnerability Reporting](https://github.com/nark/WiredSwift/security/advisories/new) to report security issues confidentially. This keeps the disclosure private until a fix is available.

### What to include

- A clear description of the vulnerability
- Steps to reproduce (proof-of-concept code if applicable)
- Affected versions
- Estimated impact (data exposure, denial of service, authentication bypass, etc.)

### What to expect

| Step | Timeline |
|------|----------|
| Acknowledgement | Within 72 hours |
| Triage & severity assessment | Within 7 days |
| Patch + coordinated disclosure | Within 90 days |

You will be credited in the release notes and GitHub Security Advisory unless you request otherwise.

## Attack Surface

WiredSwift implements the **Wired 3 (P7) binary protocol** over TCP. Key areas of concern:

- **Protocol parser** (`Sources/WiredSwift/P7/`) — TLV field parsing, length bounds checking
- **Cryptography** (`Sources/WiredSwift/Crypto/`) — ECDH key exchange, ECDSA signatures, symmetric ciphers
- **Authentication** — `wired.send_login` state machine, password hashing
- **File paths** — path traversal on `wired.file.path` fields
- **Server permissions** — 50+ `wired.account.*` permission flags

## Out of Scope

The following are not considered security vulnerabilities for this project:

- Attacks requiring physical access to the server machine
- Denial-of-service through resource exhaustion by authenticated users
- Issues in third-party dependencies (report those upstream)
- Theoretical attacks without a working proof of concept
