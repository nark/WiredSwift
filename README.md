# WiredSwift

[![CI](https://github.com/nark/WiredSwift/actions/workflows/swift.yml/badge.svg)](https://github.com/nark/WiredSwift/actions/workflows/swift.yml)
[![Swift](https://img.shields.io/badge/swift-5.4%2B-orange.svg)](https://www.swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](https://github.com/nark/WiredSwift)
[![Version](https://img.shields.io/github/v/tag/nark/WiredSwift?sort=semver)](https://github.com/nark/WiredSwift/tags)
[![License](https://img.shields.io/badge/license-BSD-blue.svg)](https://github.com/nark/WiredSwift/blob/main/LICENSE)
[![Coverage](https://img.shields.io/badge/coverage-CI%20summary-informational)](https://github.com/nark/WiredSwift/actions/workflows/swift.yml)
[![Documentation](https://img.shields.io/badge/docs-DocC-blue)](https://nark.github.io/WiredSwift/documentation/wiredswift/)

**Wired** is a bulletin board system (BBS) for group chat, private messaging, file sharing, and community administration. Originally created in 2003 by Axel Andersson at Zanka Software as a modern alternative to Hotline, it has been maintained as open-source software ever since.

A Wired server lets you host a private community where users can join public or private chat rooms, exchange messages on discussion boards, share files, and manage accounts with fine-grained permissions. All communications are encrypted end-to-end between client and server.

This repository contains the **Wired 3.0** implementation in Swift:

- **WiredSwift** — reusable Swift library for building Wired clients
- **wired3** — server daemon (macOS and Linux)
- **WiredServerApp** — macOS GUI for local server administration

The project is currently in beta. It is already usable, but it is still evolving quickly. If you want the latest version, always download the newest beta build from the project's GitHub Releases.

Releases: https://github.com/nark/WiredSwift/releases

---

## Table of Contents

- [What changed in Wired 3.0](#what-changed-in-wired-30)
  - [Features](#features)
  - [Security](#security)
  - [Comparison table](#comparison-table)
- [Getting Started as a Server Administrator](#getting-started-as-a-server-administrator)
  - [macOS with Wired Server app](#macos-with-wired-server-app)
  - [Linux with a DEB package](#linux-with-a-deb-package)
  - [Linux with an RPM package](#linux-with-an-rpm-package)
  - [Docker](#docker)
  - [Building from source on Linux](#building-from-source-on-linux)
  - [First boot and runtime layout](#first-boot-and-runtime-layout)
  - [Running as a systemd service](#running-as-a-systemd-service)
  - [Attachment behavior and quotas](#attachment-behavior-and-quotas)
  - [Securing your server](#securing-your-server)
- [Integrating WiredSwift in Your App](#integrating-wiredswift-in-your-app)
  - [Documentation hub](#documentation-hub)
- [Protocol Overview](#protocol-overview)
- [Contributing](#contributing)
  - [Local setup](#local-setup)
  - [Project layout](#project-layout)
  - [Build and test status](#build-and-test-status)
  - [Contribution priorities](#contribution-priorities)
  - [Typical workflow](#typical-workflow)
- [License](#license)

---

## What Changed in Wired 3.0

Wired 3.0 brings both major functional additions and a full overhaul of the protocol's security model.

### Features

Compared to classic Wired 2.0 deployments and clients, Wired 3.0 adds a broader set of collaborative and search capabilities:

- **Multiple public chats** instead of a single default public room, with protocol support for listing, creating, and deleting public chats
- **Live typing indicator** in chat conversations, including protocol-level typing state broadcasts
- **Board reactions** on posts, with dedicated account privilege support for adding reactions
- **Continuous folder sync** with a dedicated sync daemon (`wiredsyncd` on macOS) for keeping local folders and remote Wired shares aligned
- **Remote board search** so clients can query discussions server-side and jump directly to matching threads or snippets
- **FTS5-backed file search** on supported SQLite builds, with automatic fallback to `LIKE` queries when FTS5 is unavailable
- **Expanded search privileges** for boards and files, making search a first-class capability in the protocol and server permission model
- **A more modern platform foundation** for current Swift clients, server tooling, and GUI-based administration around the same Wired 3.0 protocol stack

#### Feature comparison (Wired 2.0 vs Wired 3.0)

| Feature | Wired 2.0 | Wired 3.0 |
|---|---|---|
| Public chats | ⚠️ Single default public room | ✅ Multiple public chats (list/create/delete) |
| Live typing indicator | ❌ Not available | ✅ Available |
| Board reactions | ❌ Not available | ✅ Available (with privilege gating) |
| Continuous folder sync | ❌ Not available | ✅ Available via `wiredsyncd` |
| Remote board search | ⚠️ Limited / client-side patterns | ✅ Server-side remote search |
| File search | ⚠️ Basic listing/search | ✅ FTS5-backed search with `LIKE` fallback |
| Server settings (admin) | ✅ Available | ✅ Available |
| Logs (admin) | ✅ Available | ✅ Available |
| Events (admin/audit) | ✅ Available | ✅ Available (including subscription and cleanup) |
| Accounts (admin) | ✅ Available | ✅ Available (list/read/create/edit/delete users/groups, subscribe changes) |
| Banlist (admin) | ✅ Available | ✅ Available |
| Tracker (admin/discovery) | ✅ Available | ✅ Available |
| Monitor (admin) | ✅ Available | ✅ Available |

### Security

Wired 3.0 is also a complete rewrite of the protocol's security layer. Here is what changed and why it matters.

#### Encryption

Wired 2.0 used **RSA key exchange** with a choice of symmetric ciphers: AES (128/192/256-bit), Blowfish-128, and 3DES-192, each combined with SHA-1, SHA-256, or SHA-512 for key derivation — 15 cipher suites total. The RSA public key was sent in the clear during the handshake.

Wired 3.0 replaces RSA with **ECDH key exchange (P-521 curve)** and offers five modern cipher suites: AES-256-CBC, AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305, and XChaCha20-Poly1305. The last four provide **authenticated encryption** (AEAD), meaning tampered data is detected and rejected automatically. Legacy ciphers (Blowfish, 3DES) are dropped entirely.

Operators can enforce `cipher = SECURE_ONLY` in `config.ini` to reject unencrypted connections.

#### Integrity checksums

Wired 2.0 supported three checksum algorithms: SHA-1, SHA-256, and SHA-512. Wired 3.0 keeps SHA2-256 and adds SHA2-384, SHA3-256, SHA3-384, and **HMAC variants** (HMAC-SHA256, HMAC-SHA384) for authenticated integrity checking — seven options total. SHA-1 is dropped. AEAD ciphers already include built-in integrity, so the checksum layer acts as defense in depth.

#### Compression

Wired 2.0 supported **DEFLATE** (zlib) compression. Wired 3.0 keeps DEFLATE and adds **LZ4** (fast, cross-platform) and **LZFSE** (high compression ratio with very good performance). LZFSE is only available on macOS servers — Linux servers fall back to DEFLATE or LZ4. Compression is applied before encryption (standard ordering to avoid CRIME/BREACH class issues).

#### Passwords

Wired 2.0 stored passwords as **unsalted SHA-1 hashes** and sent them directly over the wire, making them vulnerable to rainbow tables, GPU brute-force, and pass-the-hash attacks.

Wired 3.0 stores passwords as **SHA-256 hashes with a per-user random salt**. Authentication uses a **challenge-response protocol with ECDSA proofs**: the client proves it knows the password without ever transmitting the hash. Session salts prevent replay attacks, and a dummy hash is computed on invalid usernames to block timing-based user enumeration.

#### Admin password

Wired 2.0 shipped with a well-known default `admin / admin` password. Wired 3.0 **auto-generates a random 16-character password** on first boot and prints it to the console. There is no hardcoded default to forget about.

#### Server identity (TOFU)

Wired 2.0 had no mechanism to verify that you were connecting to the right server. A DNS spoof or network-level MITM attack could go undetected.

Wired 3.0 implements **Trust On First Use** (TOFU), similar to SSH known hosts. The server generates a persistent **P-256 ECDSA identity key** on first start and signs every session with it. Clients store the server's fingerprint on first connection. If the fingerprint changes later (possible MITM), the client warns the user and can reject the connection. Strict mode (`strict_identity = yes`, the default) makes key changes a hard failure.

#### Rate limiting

Wired 2.0 had no protection against brute-force login attempts. Wired 3.0 enforces **per-IP rate limiting** (5 failed attempts trigger a 60-second lockout), per-user chat broadcast limits (5 messages/minute), and a cap of 100 concurrent connections to prevent resource exhaustion.

### Comparison table

| | Wired 2.0 | Wired 3.0 |
|---|---|---|
| **Key exchange** | RSA | ECDH (P-521) |
| **Ciphers** | RSA + AES/Blowfish/3DES (15 suites) | ECDH + AES-GCM/ChaCha20-Poly1305 (5 suites, 4 AEAD) |
| **Password storage** | SHA-1, no salt | SHA-256, per-user salt |
| **Authentication** | Hash sent directly | Challenge-response, ECDSA proof |
| **Checksums** | SHA-1, SHA-256, SHA-512 | SHA2, SHA3, HMAC (7 options, SHA-1 dropped) |
| **Compression** | DEFLATE | DEFLATE, LZ4, LZFSE |
| **Server identity** | None | P-256 ECDSA + TOFU |
| **Rate limiting** | None | Per-IP login, per-user chat, connection cap |
| **Default admin password** | `admin` | Random, auto-generated |

---

## Getting Started as a Server Administrator

### macOS with Wired Server app

This is the recommended way to run a Wired server on a Mac. `WiredServerApp` is a native macOS GUI around `wired3`.

Requirements: macOS 14+

1. Download `Wired-Server.app.zip` from [Releases](https://github.com/nark/WiredSwift/releases)
2. Unzip and move `Wired Server.app` to `/Applications`
3. Launch the app
4. In the **General** tab, click **Install** then **Start**

Default runtime paths:

- Working directory: `~/Library/Application Support/Wired3`
- Binary: `~/Library/Application Support/Wired3/bin/wired3`
- Config: `~/Library/Application Support/Wired3/etc/config.ini`
- Database: `~/Library/Application Support/Wired3/wired3.db`
- Log file: `~/Library/Application Support/Wired3/wired.log`
- Shared files root: `~/Library/Application Support/Wired3/files`

What you can manage in the app:

- **General**: install/uninstall, start/stop, start automatically at login
- **Network**: listening port and local port check
- **Files**: files directory and reindex behavior
- **Advanced**: admin account/password + protocol security options
- **Logs**: tail-like log viewer

### Linux with a DEB package

Requirements: Debian/Ubuntu-compatible distro, matching architecture (`amd64` or `arm64`).

```bash
sudo apt update
sudo apt install ./wired3_<version>_<arch>.deb
```

Installed artifacts:

- Binary: `/usr/local/bin/wired3`
- Service unit (if included in package): `/lib/systemd/system/wired3.service`

Verify:

```bash
wired3 --version
wired3 --help
```

### Linux with an RPM package

Requirements: RPM-based distro (Fedora, RHEL, Rocky, Alma, etc.), matching architecture (`x86_64` or `aarch64`).

```bash
sudo dnf install ./wired3-<version>-<release>.<arch>.rpm
```

If your distro does not use `dnf`:

```bash
sudo rpm -Uvh wired3-<version>-<release>.<arch>.rpm
```

Installed artifacts:

- Binary: `/usr/local/bin/wired3`
- Service unit: `/usr/lib/systemd/system/wired3.service`

Verify:

```bash
wired3 --version
wired3 --help
```

### Docker

```bash
docker pull ghcr.io/nark/wired3:<tag>

docker run -d \
  --name wired3 \
  -p 4871:4871 \
  -v wired3-data:/var/lib/wired3 \
  ghcr.io/nark/wired3:<tag>
```

Notes:

- Runtime data is stored under `/var/lib/wired3` (persist with a volume).
- The container bootstraps `wired.xml`, `banner.png`, and `config.ini` automatically on first run.
- To run a specific architecture locally, add `--platform linux/amd64` or `--platform linux/arm64`.
- Release automation publishes multiple tags (version/build, release tag, commit, and optionally `latest` on stable).

Verify:

```bash
docker logs -f wired3
docker exec wired3 wired3 --version
```

### Building from source on Linux

Install dependencies (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y liblz4-dev libsqlite3-dev libssl-dev zlib1g-dev

curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && \
tar zxf swiftly-$(uname -m).tar.gz && \
./swiftly init --quiet-shell-followup && \
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh" && \
hash -r
```

Build:

```bash
git clone https://github.com/nark/WiredSwift.git
cd WiredSwift
swift build -c release --product wired3 -Xswiftc -DGRDBCUSTOMSQLITE
```

Run binary:

```bash
.build/release/wired3 --version
```

Optional install:

```bash
sudo install -m 755 .build/release/wired3 /usr/local/bin/wired3
```

### First boot and runtime layout

`wired3` needs a runtime directory. At first start, it creates defaults such as config, logs, DB, and files root.

Typical runtime content:

- `etc/config.ini`
- `wired3.db`
- `wired.log`
- `files/`
- `wired.xml` (protocol spec)

Important for Linux package users:

- The `.deb` package installs the daemon binary, but your runtime spec file path still matters.
- Provide `--spec` explicitly, or place `wired.xml` in a path your startup command references.

Example runtime setup:

```bash
sudo mkdir -p /var/lib/wired3/{etc,files}
sudo chown -R wired3:wired3 /var/lib/wired3
```

Then run with explicit paths:

```bash
sudo -u wired3 wired3 \
  --working-directory /var/lib/wired3 \
  --config /var/lib/wired3/etc/config.ini \
  --db /var/lib/wired3/wired3.db \
  --spec /var/lib/wired3/wired.xml
```

### Running as a systemd service

Recommended service pattern:

```ini
[Unit]
Description=Wired 3 server
After=network.target

[Service]
Type=simple
User=wired3
Group=wired3
WorkingDirectory=/var/lib/wired3
ExecStart=/usr/local/bin/wired3 --working-directory /var/lib/wired3 --config /var/lib/wired3/etc/config.ini --db /var/lib/wired3/wired3.db --spec /var/lib/wired3/wired.xml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and run:

```bash
sudo systemctl daemon-reload
sudo systemctl enable wired3
sudo systemctl start wired3
```

Operate:

```bash
sudo systemctl status wired3
sudo journalctl -u wired3 -f
sudo systemctl restart wired3
```

### Attachment behavior and quotas

The server enforces the following limits on attachments:

- **Maximum attachment size**: 16 MB per file
- **Maximum preview size**: 1 MB (for inline previews)
- **Maximum attachments per message**: 8 files
- **Maximum total attachment bytes per message**: 32 MB
- **Maximum persistent board storage**: 512 MB (shared across all boards)
- **Chunk size limit**: 256 KB per upload/download chunk
- **Staging TTL**: 10 minutes (for incomplete uploads)
- **Chat ephemeral TTL**: 10 minutes (for chat attachments)
- **Direct message ephemeral TTL**: 30 days (for direct message attachments)

Attachments are stored in different locations depending on their scope:

- **Staging**: Temporary storage for incomplete uploads (`attachments/staging/`)
- **Ephemeral**: Short-lived attachments for chats and direct messages (`attachments/ephemeral/`)
- **Persistent**: Long-lived attachments for boards (`attachments/store/`)

The server automatically cleans up expired attachments every 30 seconds.


### Securing your server

#### Admin password

At database bootstrap (first start), two default accounts are created automatically:

| Login | Default password | Role |
|-------|-----------------|------|
| `admin` | *random, printed to console* | Full privileges |
| `guest` | *(empty)* | Read-only |

On first boot the server generates a random 16-character admin password and prints it to stdout (look for `===INITIAL ADMIN PASSWORD===` in the log). **Copy it immediately** — it is only shown once.

You can change the admin password at any time:

- **WiredServerApp** → **Advanced** tab → "Admin account" section → type a new password → **Set Password**
- **CLI / Linux**: connect with any Wired 3 client, log in as `admin` with the generated password, open the admin panel and change it

The server stores passwords as SHA-256 hashes with a per-user salt. There is no plain-text recovery — if you lose the admin password you must reset it via direct database access:

```bash
# Replace <hash> with SHA-256 of your new password
sqlite3 wired3.db "UPDATE users SET password = '<sha256_of_password>' WHERE username = 'admin';"
```

#### Server identity and TOFU

Starting from P7 protocol v1.3, the server generates a **persistent identity key** (P-256 ECDSA) used for Trust On First Use (TOFU) protection against man-in-the-middle attacks.

**How it works:**

1. On first start, `wired3` generates a private key stored in `<working-dir>/wired-identity.key`
2. On every connection, the server signs the ephemeral session key with this identity key
3. Clients receive the identity public key and its fingerprint
4. On first connection to a server, clients store the fingerprint
5. On subsequent connections, clients compare the received fingerprint to the stored one
   - If it matches → connection is allowed (green "Verified Identity" badge in the client)
   - If it differs and `strict_identity = yes` → connection is **rejected** (possible MITM attack)
   - If it differs and `strict_identity = no` → fingerprint is updated silently (useful during migration)

**Viewing the fingerprint (WiredServerApp):**

1. Open **WiredServerApp** → **Advanced** tab
2. The "Server Identity (TOFU)" section shows:
   - A green dot and the `SHA256:xx:xx:...` fingerprint if the key exists
   - A red dot and a help message if the server has not been started yet

**Exporting the public key:**

Use the **Export Public Key** button to save a Base64-encoded copy of the server's identity public key. Distribute this file out-of-band (e.g., via your website or email) so users can verify they are connecting to the right server.

**Rotating the identity key:**

If the server is compromised or you intentionally rotate the key:

1. Stop the server
2. Delete `<working-dir>/wired-identity.key`
3. Start the server — a new key is generated automatically
4. Notify your users: they will see a "key changed" warning on next connection and must re-trust the new fingerprint

**Temporarily disabling strict mode** (e.g., during migration):

```ini
# in config.ini
[security]
strict_identity = no
```

Re-enable strict mode once all clients have updated their stored fingerprint.

**Linux / CLI — view the fingerprint:**

```bash
# OpenSSL one-liner (requires the base64-encoded public key)
openssl dgst -sha256 -binary wired-identity-public.b64 | xxd -p | fold -w2 | paste -sd':'
```

Or use `wired3 --print-identity` (if available in your build):

```bash
wired3 --working-directory /var/lib/wired3 --print-identity
```

#### Hardening checklist

1. Change the admin password (see above)
2. Restrict network exposure (firewall, private interfaces)
3. Run the service as a dedicated non-root user (`wired3` on Linux)
4. Keep `strict_identity = yes` in `config.ini`
5. Distribute the server identity fingerprint to users out-of-band

---

## Integrating WiredSwift in Your App

The full integration guide has moved to DocC and is now the source of truth for API usage and code examples.

### Documentation hub

- Main DocC portal: https://nark.github.io/WiredSwift/documentation/wiredswift/
- Getting started guide: https://nark.github.io/WiredSwift/documentation/wiredswift/gettingstarted/
- Connection patterns: https://nark.github.io/WiredSwift/documentation/wiredswift/connectionpatterns/
- Operations and Docker: https://nark.github.io/WiredSwift/documentation/wiredswift/operations/
- Protocol and security: https://nark.github.io/WiredSwift/documentation/wiredswift/protocolandsecurity/

---

## Protocol Overview

Wired is built on **P7**, a custom binary protocol designed for low-overhead, structured messaging over TCP. All communication between clients and the server uses P7 messages.

**Message format:** each P7 message is a binary frame consisting of a 4-byte message ID (big-endian), a 4-byte total length, and a sequence of TLV (type-length-value) fields. Each field carries a 4-byte field ID, a 4-byte value length, and the raw value bytes. This compact encoding avoids the overhead of text-based formats like XML or JSON while remaining easy to parse.

**Protocol specification:** the full catalog of messages, fields, and data types is declared in `wired.xml`, a machine-readable XML file shipped with every server. Clients load this spec at connection time to know which messages exist and how to encode/decode them. When the protocol evolves, only `wired.xml` needs to be updated — the parser, serializer, and network layer adapt automatically.

**Session lifecycle:** a typical session flows through handshake (version and capability negotiation), key exchange (ECDH + optional identity verification), authentication (challenge-response), and then enters steady-state messaging (chat, file transfers, board operations, admin commands). Each phase is a well-defined sequence of P7 messages documented in `wired.xml`.

For implementation details, see `Sources/WiredSwift/P7/` (parser, socket, spec loader) and `Sources/wired3/` (server-side message handlers).

---

## Contributing

### Local setup

```bash
git clone https://github.com/nark/WiredSwift.git
cd WiredSwift
swift build -v
```

### Project layout

- `Sources/WiredSwift`: library implementation
- `Sources/wired3`: server daemon
- `Sources/WiredServerApp`: macOS wrapper UI
- `Scripts/debian`: Debian packaging assets (`control`, maintainer scripts, systemd unit)
- `Scripts/build-wired-server-app.sh`: macOS app packaging script
- `.github/workflows/build-linux-deb-packages.yml`: CI workflow for amd64/arm64 `.deb` artifacts

### Build and test status

As of March 2026:

- `swift build -c release --product wired3` succeeds locally
- Linux CI build command: `swift build -c release --product wired3 -Xswiftc -DGRDBCUSTOMSQLITE`
- Some tests still target an older `Connection.connect` API shape and currently fail to compile

If you submit a PR touching networking APIs, include test updates when signatures change.

### Contribution priorities

- Protocol correctness and compatibility
- Socket I/O reliability
- Multi-thread/concurrency robustness
- Regression-resistant test coverage
- Server operational stability

### Typical workflow

1. Open an issue describing bug/feature scope
2. Submit a focused PR
3. Add/update tests and docs for behavior changes
4. Include migration notes if public API changed

---

## License

BSD license. See [LICENSE](LICENSE).

- Copyright (c) 2003-2009 Axel Andersson
- Copyright (c) 2011-2020 Rafaël Warnault
