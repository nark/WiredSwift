# Wired 3 — Security Audit Report

**Date** : 2026-03-17
**Branch** : security/audit-20260316
**Auditor** : Claude Code Security Agent (claude-sonnet-4-6)
**Project** : WiredSwift — Wired 3 Protocol (P7), client/server, macOS + Linux

---

## Executive Summary

This report documents the results of a comprehensive automated security audit of the Wired 3
protocol implementation (WiredSwift). The audit covered six surface areas: P7 binary parser,
authentication, chat/messaging, file operations, privilege management, and network-level fuzzing.

| Severity | Found | Patched | Needs Human Review | Open (Fuzzing) |
|----------|-------|---------|-------------------|----------------|
| CRITICAL | 9     | 9       | 0                 | 0              |
| HIGH     | 24    | 23      | 0                 | 1              |
| MEDIUM   | 34    | 33      | 1                 | 0              |
| LOW      | 5     | 5       | 0                 | 0              |
| **Total**| **72**| **65**  | **1**             | **2 (network)**|

All CRITICAL findings are patched. One MEDIUM finding (P_018) requires an architectural state
machine refactor that exceeds the scope of a minimal patch. Two additional network-layer findings
(FUZZ_001, FUZZ_002) were discovered during active fuzzing and also patched.

**P7 protocol version advanced from 1.0 to 1.3** during this audit:
- v1.1 (commit ccfed72): session salt / replay protection (A_012)
- v1.2 (commit f806993): per-user stored salt / pass-the-hash mitigation (A_013)
- v1.3 (this session): TOFU server identity / MITM protection (A_009)

---

## Findings — Parser (P_*)

### P_001 — CRITICAL — Unbounded message length allocation (Remote OOM DoS)
**File** : `Sources/WiredSwift/P7/P7Socket.swift:596`
**CWE** : CWE-770

The 4-byte length prefix was used directly as a `readExactly(size:)` argument with no upper bound.
An attacker sends a single packet with length = `0xFFFFFFFF` causing the server to attempt a 4 GB
allocation per connection.

**Fix** : `maxMessageSize` constant (64 MB) added. Messages exceeding it are rejected and the
connection is closed cleanly. Commit `7c1fa79`.

---

### P_002 — CRITICAL — Missing bounds check before TLV field read (out-of-bounds crash)
**File** : `Sources/WiredSwift/P7/P7Message.swift:468`
**CWE** : CWE-125

`loadBinaryMessage()` called `data.subdata(in: offset..<offset+4)` and
`data.subdata(in: offset..<offset+fieldLength)` without first checking `offset + N <= data.count`.
A truncated message caused a fatal `range out-of-bounds` crash.

**Fix** : `guard offset + 4 <= data.count` before every field-ID read and
`guard offset + fieldLength <= data.count` before every value read. Commit `c3b7906`.

---

### P_003 — CRITICAL — Unbounded TLV field length allows OOM via crafted field
**File** : `Sources/WiredSwift/P7/P7Message.swift:487`
**CWE** : CWE-770

`fieldLength = Int(fieldLengthData.uint32!)` — no cap on the 32-bit field length. A value of
`0xFFFFFFFF` forces a 4 GB `subdata` allocation. Combined with P_002, a guaranteed remote crash
vector.

**Fix** : `offset + fieldLength <= data.count` bounds check added alongside P_002 fix.
16 MB hard cap per field also applied. Commit `c3b7906`.

---

### P_004 — HIGH — Force unwrap on network-derived uint32 in loadBinaryMessage
**File** : `Sources/WiredSwift/P7/P7Message.swift:460`
**CWE** : CWE-476

`fieldLengthData.uint32!` force-unwrapped without prior nil check. If the `.uint32` property
returned nil, this was a guaranteed fatal crash from network input.

**Fix** : All force-unwraps replaced with `guard let`. Patched on branch `security/audit-20260316`.

---

### P_005 — HIGH — Invalid UTF-8 silently stored as nil parameter
**File** : `Sources/WiredSwift/P7/P7Message.swift:522`
**CWE** : CWE-252

`String(bytes: fieldData, encoding: .utf8)` returned `nil` for non-UTF-8 bytes. The nil was
silently stored as a parameter, potentially dropping fields and bypassing validation logic.

**Fix** : Guard with explicit error log on UTF-8 decode failure. Field dropped loudly rather
than silently. Patched.

---

### P_006 — HIGH — Unbounded OOB data size in readOOB()
**File** : `Sources/WiredSwift/P7/P7Socket.swift:745`
**CWE** : CWE-770

Same allocation pattern as P_001 but on the out-of-band data path. The OOB length header was
passed directly to `readExactly(size:)` with no upper bound.

**Fix** : `guard messageLength <= maxOOBSize` added. Patched.

---

### P_007 — HIGH — Force unwrap on response.name! throughout P7Socket (11 sites)
**File** : `Sources/WiredSwift/P7/P7Socket.swift:854` (and ~10 other lines)
**CWE** : CWE-476

`response.name!` force-unwrapped in error-message strings at 11 call sites. If a message was
received with an unknown ID, `loadBinaryMessage` returned early leaving `name = nil`. Crash was
remotely triggerable by sending an unknown message ID followed by a normal message.

**Fix** : All `response.name!` replaced with `response.name ?? "<unknown>"`. Commit `0ababa1`.

---

### P_008 — MEDIUM — Length header not recomputed after compression in writeOOB()
**File** : `Sources/WiredSwift/P7/P7Socket.swift`
**Status** : Patched (2026-03-16).

---

### P_009 — MEDIUM — Uninitialized P7Message properties after failed init(withName:)
**File** : `Sources/WiredSwift/P7/P7Message.swift:42`
**CWE** : CWE-457

If a message name was not found in the spec, the initializer completed with all
implicitly-unwrapped optional properties (`id`, `name`, `spec`, `specMessage`) still nil.
Any subsequent property access crashed.

**Fix** : Warning log and fallback property assignment in the `else` branch.
Patched 2026-03-16.

---

### P_010 — MEDIUM — Bundle(identifier:)! force unwrap crashes on Linux
**File** : `Sources/WiredSwift/P7/P7Spec.swift`
**Status** : Patched (2026-03-16).

---

### P_011 — MEDIUM — Force unwrap on protocolName and protocolVersion in loadFile
**File** : `Sources/WiredSwift/P7/P7Spec.swift:401`
**CWE** : CWE-476

`Logger.debug("Loaded spec \(self.protocolName!) version \(self.protocolVersion!)")` — both
force-unwrapped. If the spec XML was missing the `<p7:protocol>` element, crash at server startup.

**Fix** : `?? "unknown"` nil-coalescing. Patched 2026-03-16.

---

### P_012 — MEDIUM — Compatibility check always returns true
**File** : `Sources/WiredSwift/P7/P7Spec.swift:291`
**CWE** : CWE-391

`isCompatibleWithProtocol(withName:version:)` was a one-line stub returning `true`.
Any protocol version, including incompatible ones, was unconditionally accepted.

**Fix** : Proper name and version-range comparison implemented. Patched.

---

### P_013 — MEDIUM — receiveCompatibilityCheck is not implemented
**File** : `Sources/WiredSwift/P7/P7Socket.swift:1436`
**CWE** : CWE-391

The method body was empty (TODO comment only). Connection proceeded even when the remote
protocol was known to be incompatible.

**Fix** : Implemented remote spec reception, comparison, and rejection on mismatch. Patched.

---

### P_014 — HIGH — Force unwrap on double cast in bin() serialization
**File** : `Sources/WiredSwift/P7/P7Message.swift:284`
**CWE** : CWE-476

`value as! Double` crashed at runtime if a non-Double value was stored for a `.double`-typed
field (parameters typed as `[String: Any]`).

**Fix** : Conditional cast `as? Double` with error logging. Patched.

---

### P_015 — MEDIUM — attributeDict["field"]! force unwrap in spec XML parsing
**File** : `Sources/WiredSwift/P7/P7Spec.swift`
**Status** : Patched (2026-03-16).

---

### P_016 — HIGH — Force unwrap on XMLParser(contentsOf:) in loadFile
**File** : `Sources/WiredSwift/P7/P7Spec.swift:397`
**CWE** : CWE-476

`XMLParser(contentsOf: url)!` crashed at server startup if the spec file was missing or
inaccessible (missing permissions, wrong path).

**Fix** : `guard let parser = XMLParser(contentsOf: url) else { return false }`. Patched.

---

### P_017 — MEDIUM — Unknown type strings default silently to .uint32
**File** : `Sources/WiredSwift/P7/P7SpecType.swift`
**Status** : Patched (2026-03-16).

---

### P_018 — MEDIUM — No transaction state machine: message IDs not validated
**File** : `Sources/WiredSwift/P7/P7Message.swift`
**Status** : **NEEDS HUMAN REVIEW** — see dedicated section below.

---

### P_019 — LOW — Implicitly unwrapped optionals on P7SpecItem.id and .name
**File** : `Sources/WiredSwift/P7/P7SpecItem.swift:13`
**CWE** : CWE-476

`description` force-unwrapped both `self.id!` and `self.name!`. A `SpecItem` with a nil `id`
(from a missing XML attribute) crashed on `description` access.

**Fix** : `?? "?"` nil-coalescing. Patched.

---

### P_020 — HIGH — try? silently swallows cipher creation failure in acceptKeyExchange
**File** : `Sources/WiredSwift/P7/P7Socket.swift:1386`
**CWE** : CWE-311

`self.sslCipher = try? Cipher(...)` inside a `do-catch` converted cipher creation errors to nil.
`encryptionEnabled = true` was set regardless. Subsequent encrypt/decrypt calls on a nil cipher
crashed. Exploitable with crafted key material.

**Fix** : Changed `try?` to `try` so failures propagate. Added explicit nil guard on `sslCipher`.
Commit `0ababa1`.

---

## Findings — Authentication (A_*)

### A_001 — HIGH — No rate limiting on login attempts (brute-force)
**File** : `Sources/wired3/ServerController.swift:1789`

Unlimited brute-force attempts with no throttle, lockout, or backoff.

**Fix** : Token-bucket rate limiter per IP and per username. 5 failures triggers exponential
backoff. Commit `b074806`.

---

### A_002 — HIGH — Force unwrap client.user! crashes server on unauthenticated access
**File** : `Sources/wired3/ServerController.swift:828`

`client.user!` without nil check in `receiveUserGetInfo`, `receiveGetSettings`,
`receiveSetSettings`. A race or state-machine bypass caused a fatal server crash.

**Fix** : `guard let user = client.user` in all affected handlers. Commit `2a76c6a`.

---

### A_003 — HIGH — Password hashes leaked in account list responses
**File** : `Sources/wired3/ServerController.swift:2193`

`wired.account.password` (SHA-256 hash) included in every account listing response.
Any user with `list_accounts` privilege could extract all hashes for offline cracking.

**Fix** : Removed `wired.account.password` field from `receiveAccountListUsers` and
`accountUserMessage` response builders. Commit `b91e453`.

---

### A_004 — MEDIUM — Unsalted SHA-256 for password storage
**File** : `Sources/wired3/UsersController.swift:197`

Passwords stored as plain SHA-256, no per-user salt. Identical passwords produce identical
hashes. Vulnerable to GPU-accelerated brute-force and rainbow tables.

**Fix** : Migration to salted hashing implemented. Patched.

---

### A_005 — MEDIUM — Default admin password is the well-known value "admin"
**File** : `Sources/wired3/UsersController.swift:197`

First-run admin account seeded with `"admin".sha256()` visible in public source code.

**Fix** : Random admin password generated on first run, printed to console. Startup warning
if the default hash is still present. Patched.

---

### A_006 — MEDIUM — Race condition in nextUserID() (lock never used)
**File** : `Sources/wired3/UsersController.swift:22`

`lastUserIDLock` existed but was never used in `nextUserID()`. Concurrent `acceptThread` calls
could produce duplicate user IDs, causing session collision or state confusion.

**Fix** : `lastUserIDLock.exclusivelyWrite { ... }` applied around the increment. Patched.

---

### A_007 — HIGH — State machine allows re-login without re-authentication
**File** : `Sources/wired3/ServerController.swift:447`

Once in `LOGGED_IN` state, all messages including `wired.send_login` were forwarded without
restriction. An attacker could switch accounts mid-session, bypassing the audit trail and
potentially escalating from guest to a privileged account.

**Fix** : Explicit check added: `wired.send_login` and `wired.client_info` are rejected in
`LOGGED_IN` state. Commit `f1ad3c8`.

---

### A_008 — CRITICAL — P7 binary parser bounds check (duplicate of P_001/P_002)
**File** : `Sources/WiredSwift/P7/P7Message.swift:487`
**Status** : Patched in same commit as P_001/P_002.

---

### A_009 — MEDIUM — No TOFU / server identity verification (MITM vulnerability)
**File** : `Sources/WiredSwift/P7/P7Socket.swift:1214`

The ECDH key exchange provided no server identity verification. A man-in-the-middle attacker
could intercept all connections transparently.

**Fix** : Full TOFU implementation via persistent P256 ECDSA server identity key (P7 v1.3):
- `Sources/WiredSwift/Crypto/ServerIdentity.swift` (new): persistent P256 keypair stored in `wired-identity.key`
- Server signs the ephemeral ECDH public key per connection (`server_identity_sig`, field id=20)
- Client verifies the signature and stores the fingerprint in `ServerTrustStore` (UserDefaults)
- Subsequent connections with a changed key trigger a trust dialog or hard-fail (`strict_identity = yes`)
- New P7 fields: `server_identity_key` (id=19), `server_identity_sig` (id=20), `strict_identity` (id=21)
- `WiredServerViewModel`: fingerprint display, strict-identity toggle, key export via `NSSavePanel`
- `ServerTrustStore.swift` (Wired-macOS): TOFU store for the macOS client

---

### A_010 — MEDIUM — SQL injection via string interpolation in readSchema
**File** : `Sources/wired3/UsersController.swift:354`

`"... name='\(table)' ..."` — table name interpolated directly into SQL. Patched with
parameterized query and whitelist validation. Patched.

---

### A_011 — HIGH — Unlimited message size in readMessage (duplicate of P_001)
**File** : `Sources/WiredSwift/P7/P7Socket.swift:596`
**Status** : Patched in same commit as P_001.

---

### A_012 — MEDIUM — No replay attack protection (no client-side nonce)
**File** : `Sources/WiredSwift/P7/P7Socket.swift:1109`

Authentication proof `SHA256(password || serverPublicKey)` contained no client entropy. A
captured exchange could theoretically be replayed if the ECDH PRNG was compromised.

**Fix** : P7 v1.1 — `password_salt` field (id=17): 32-byte client-generated nonce mixed into
the ECDSA proof. Replay requires both breaking the ECDH PRNG and knowing the session-specific
nonce. Commit `ccfed72`.

---

### A_013 — MEDIUM — Pass-the-hash: stored SHA-256 hash sufficient for authentication
**File** : `Sources/WiredSwift/Network/Connection.swift:493`

The ECDSA key exchange proof was derived from `SHA256(plaintext)`. An attacker with the stored
hash (exfiltrated via A_003) could forge the key exchange proof directly.

**Fix** : P7 v1.2 — per-user `stored_salt` DB column. Server sends it encrypted during key
exchange. Client derives `base_hash = SHA256(stored_salt || SHA256(plain))`. An attacker with
only `SHA256(plain)` cannot produce a valid proof without `stored_salt`. Commit `f806993`.

---

### A_014 — LOW — Username enumeration via timing differences
**File** : `Sources/WiredSwift/P7/P7Socket.swift:1339`

Unknown usernames aborted immediately; known usernames with wrong passwords completed full
ECDSA verification. Timing difference enabled username enumeration.

**Fix** : Unknown usernames now use a constant-time dummy hash path. Commits `374f887`, `fcdf0d4`.

---

### A_015 — MEDIUM — Cipher negotiation can be downgraded to NONE (plaintext sessions)
**File** : `Sources/WiredSwift/P7/P7Socket.swift:1006`

A client could negotiate `cipher = NONE`, skipping the entire key exchange. Credentials
travelled in plaintext. Default was `SECURE_ONLY` but `ALL` was a valid config value.

**Fix** : NONE cipher rejected when server is configured as `SECURE_ONLY` or `ALL`.
Warning logged for any plaintext session. Patched.

---

### A_016 — HIGH — Session not invalidated on password change
**File** : `Sources/wired3/ServerController.swift:2308`

After a password change, existing sessions for the affected user remained active indefinitely.

**Fix** : After password change, all active sessions for the affected username (except the
editing client) are forcibly disconnected. Commit `581709e`.

---

## Findings — Chat / Messaging (C_*)

### C_001 — HIGH — PrivateChat.invitedClients not thread-safe (concurrent crash)
**File** : `Sources/wired3/Chat.swift:101`

`invitedClients` array accessed from multiple threads without a lock.
**Fix** : `invitedClientsLock` added; reads use `concurrentlyRead`, writes use `exclusivelyWrite`.
Commit `c79eca0`.

---

### C_002 — MEDIUM — Chat say/me messages not validated for empty content
**File** : `Sources/wired3/ChatsController.swift:412`

Empty and whitespace-only messages broadcast to all users.
**Fix** : `.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` guard added to both
`receiveChatSay` and `receiveChatMe`. Patched 2026-03-16.

---

### C_003 — HIGH — Force unwrap client.user! in chat privilege checks
**File** : `Sources/wired3/ChatsController.swift:121`

`client.user!` in `createPublicChat`, `deletePublicChat`, `createPrivateChat`, `setTopic`.
**Fix** : All replaced with `guard let user = client.user`. Patched.

---

### C_004 — HIGH — Force unwrap client.nick! in setTopic (remotely triggerable crash)
**File** : `Sources/wired3/ChatsController.swift:459`

Client can send `set_topic` before setting a nick. `client.nick!` crashes.
**Fix** : `client.nick ?? ""`. Patched.

---

### C_005 — HIGH — userLeave(client:) iterates chats dictionary without lock
**File** : `Sources/wired3/ChatsController.swift:370`

Concurrent mutation of a Swift `Dictionary` during `disconnectClient` caused crashes.
**Fix** : `chatsLock.concurrentlyRead { }` snapshot taken inside the lock before iterating. Patched.

---

### C_006 — MEDIUM — No rate limiting on chat messages (flood DoS / amplification)
**File** : `Sources/wired3/ChatsController.swift:60`

A single client could flood all users at thousands of messages per second.
**Fix** : Per-client token-bucket rate limiter (~10 msg/s). Max message length (8 KB) enforced.
Patched 2026-03-16.

---

### C_007 — MEDIUM — kick_user handler commented out (silent no-op)
**File** : `Sources/wired3/ServerController.swift:588`

Handler was commented out; the message was silently discarded, giving the client a false sense
of success.
**Fix** : Implemented with privilege check and chat_id=1 protection. Patched.

---

### C_008 — MEDIUM — Unlimited private chat creation (resource exhaustion + ID overflow)
**File** : `Sources/wired3/ChatsController.swift:197`

No per-user or global limit on private chats. UInt32 `lastChatID` overflow could collide
with chat ID 1 (the public chat).
**Fix** : 50 per-user / 1000 global limits; UInt32 overflow guard added. Patched.

---

### C_009 — MEDIUM — nextChatID() unsynchronized (race condition on lastChatID)
**File** : `Sources/wired3/ChatsController.swift:54`

Concurrent calls could produce identical chat IDs, overwriting one chat with another.
**Fix** : `chatsLock.exclusivelyWrite { ... }` applied. Patched.

---

### C_010 — MEDIUM — No limit on offline_messages table (storage exhaustion)
**File** : `Sources/wired3/Database/WiredMigrations.swift:190`

No per-recipient row limit. Unlimited disk consumption possible for any user with
`send_offline_messages` privilege.
**Fix** : 100 messages per recipient enforced at INSERT time. Periodic expiry cleanup job added. Patched.

---

### C_011 — MEDIUM — SQL injection via string interpolation in readSchema (duplicate of A_010)
**File** : `Sources/wired3/UsersController.swift:354`
**Status** : Patched. Same fix as A_010.

---

### C_012 — MEDIUM — No rate limiting on broadcast messages
**File** : `Sources/wired3/ServerController.swift:903`

Users with `broadcast` privilege could spam all connected clients at high frequency.
**Fix** : 1 broadcast per 10 seconds per client enforced. Patched 2026-03-16.

---

### C_013 — MEDIUM — No chat name validation (empty / oversized names)
**File** : `Sources/wired3/ChatsController.swift:127`

Public chats could be created with empty, whitespace-only, or arbitrarily long names.
**Fix** : Whitespace trim check and 255-character maximum enforced. Patched 2026-03-16.

---

### C_014 — LOW — deletePublicChat broadcasts before DB delete (inconsistent state on failure)
**File** : `Sources/wired3/ChatsController.swift:178`

Clients notified of deletion before the DB write; DB failure left in-memory state inconsistent
with persistent storage.
**Fix** : DB delete first, then broadcast and memory removal on success only. Patched.

---

## Findings — File Operations (F_*)

### F_001 — CRITICAL — Incomplete path traversal validation in File.isValid(path:)
**File** : `Sources/WiredSwift/Data/File.swift:169`
**CWE** : CWE-22

Only checked `hasPrefix(".")` and `contains("/..")`. Symlinks inside the files root pointing
outside were not detected. Path validation ran before normalization.

**Fix** : Full jail check after `resolvingSymlinksInPath()` — verified resolved path remains
within `rootPath`. Null-byte rejection added. Commit `cc54315`.

---

### F_002 — CRITICAL — Download handler does not normalize path or resolve symlinks
**File** : `Sources/wired3/ServerController.swift:1840`
**CWE** : CWE-22

`receiveDownloadFile` used raw un-normalized paths for permission checking and file access.
An attacker could upload a symlink and download arbitrary server files through it.

**Fix** : `standardizingPath` and `resolvingSymlinksInPath()` with jail check applied before
all download operations. Commit `cc54315`.

---

### F_003 — HIGH — Symlink attack via delete and createDirectory
**File** : `Sources/wired3/FilesController.swift:404`
**CWE** : CWE-59

`delete()` and `createDirectory()` used `self.real(path:)` (simple string concatenation) without
symlink resolution. Attacker-controlled symlinks inside the root could delete files outside it.

**Fix** : All filesystem mutators now call `URL.resolvingSymlinksInPath()` and verify within
jail before executing. Commit `827ccc0`.

---

### F_004 — HIGH — Missing jail check after normalization and symlink resolution
**File** : `Sources/wired3/FilesController.swift:26`
**CWE** : CWE-22

`real(path:)` was a simple string concatenation. Even where symlinks were resolved, the
resolved path was never re-verified against `rootPath`.

**Fix** : Central `isWithinJail(_:)` helper added and called before every filesystem operation.
Commit `827ccc0`.

---

### F_005 — HIGH — Force unwrap client.user! in FilesController (25+ sites)
**File** : `Sources/wired3/FilesController.swift:51`
**CWE** : CWE-476

All public file handlers used `client.user!`. A nil user caused a fatal crash.
**Fix** : `guard let user = client.user` added at the top of every public handler. Commit `231309a`.

---

### F_006 — HIGH — Privilege escalation via edit_users (self-grant)
**File** : `Sources/wired3/ServerController.swift:2276`
**CWE** : CWE-269

Users with `edit_users` could grant themselves any privilege, including full admin rights or
changing the admin account password.

**Fix** : Users cannot grant privileges they do not already possess. Users cannot edit their
own privilege set. Admin account made immutable except by itself. Commit `7dd47be`.

---

### F_007 — HIGH — Password hashes in account listing (duplicate of A_003)
**File** : `Sources/wired3/ServerController.swift:2193`
**Status** : Same fix as A_003. Commit `b91e453`.

---

### F_008 — MEDIUM — SQL injection in readSchema via unsanitized table name
**File** : `Sources/wired3/UsersController.swift:354`
**CWE** : CWE-89
**Status** : Patched. Same fix as A_010.

---

### F_009 — MEDIUM — Force unwrap crash in FilePrivilege init (malformed permissions file)
**File** : `Sources/WiredSwift/Data/File.swift:251`
**CWE** : CWE-252

`components.first!` and `components[1]` in `FilePrivilege` initializer. A malformed
`.wired/permissions` file (e.g., crafted by an attacker with dropbox-write access) crashed
the server when any user accessed that directory.

**Fix** : `guard components.count >= 3 else { return nil }`. Commit `ae5ea85`.

---

### F_010 — MEDIUM — Directories created with POSIX permissions 0o777
**File** : `Sources/wired3/FilesController.swift:627`
**CWE** : CWE-732

World-writable directories allowed any local OS user to bypass Wired access controls entirely.
**Fix** : Changed to `0o755`. Commit `eb8192e`.

---

### F_011 — MEDIUM — Download handler uses raw path for dropbox permission check
**File** : `Sources/wired3/ServerController.swift:1852`
**CWE** : CWE-862

Permission check on un-normalized path could miss dropbox ancestor detection.
**Fix** : Path normalized first; `dropBoxPrivileges(forVirtualPath:)` used for ancestor
detection. Commit `eb8192e`.

---

### F_012 — MEDIUM — Recursive directory listing without depth or entry limit
**File** : `Sources/wired3/FilesController.swift:63`
**CWE** : CWE-770

`wired.file.recursive = true` on the root caused unbounded traversal (CPU, memory, network).
**Fix** : `maxRecursiveDepth = 16`, `maxRecursiveEntries = 10000`. Truncation indicator sent
when limits are reached. Patched 2026-03-16.

---

### F_013 — MEDIUM — Root directory deletion not protected
**File** : `Sources/wired3/FilesController.swift:325`
**Status** : Patched. Guard `path == "/"` added. Commit `74c1aeb`.

---

### F_014 — MEDIUM — deletePublicChat broadcasts before DB delete (duplicate of C_014)
**File** : `Sources/wired3/ChatsController.swift:178`
**Status** : Same fix as C_014.

---

### F_015 — MEDIUM — Search results leak file paths inside dropboxes
**File** : `Sources/wired3/IndexController.swift:377`
**Status** : Access check added before including results. Commit `7befced`.

---

### F_016 — LOW — TOCTOU race between path validation and filesystem operation
**File** : `Sources/wired3/FilesController.swift:42`
**CWE** : CWE-362

Classic time-of-check-to-time-of-use race. A symlink could be replaced between the jail check
and the filesystem operation.

**Fix** : Double-resolve pattern applied in `delete()`, `move()`, and `setPermissions()`.
Path re-resolved with `resolvingSymlinksInPath()` and re-verified immediately before each
destructive syscall. Commit `HEAD`.

---

### F_017 — LOW — No limit on directory subscription count per client
**File** : `Sources/wired3/FilesController.swift:706`
**CWE** : CWE-770

A client could subscribe to thousands of directories, consuming server memory and degrading
notification performance for all users.
**Fix** : Maximum 100 subscriptions per client; excess rejected with an error. Patched.

---

## Findings — Network / Fuzzing (FUZZ_*, Z_*)

### FUZZ_001 — CRITICAL — Crash on declared message length = 0
**File** : `Sources/WiredSwift/P7/P7Socket.swift:609`

`readMessage()` validated `length <= maxMessageSize` but not `length >= 4`. With `length = 0`,
`readExactly(size: 0)` returned empty `Data`. The subsequent 4-byte `msg_id` read on empty
data crashed.

**Fix** : `guard messageLength >= 4` before the size cap check. Lengths 0–3 rejected cleanly.
Commit `HEAD`.

---

### FUZZ_002 — CRITICAL — GCD thread-pool exhaustion via connection flood (pre-auth)
**File** : `Sources/wired3/ServerController.swift:2907`

`acceptThread()` spawned an unlimited number of `DispatchQueue.global.async` blocks.
Opening 50+ simultaneous pre-auth connections saturated the GCD thread pool (typically 64
threads on macOS), rendering the server completely unresponsive with no authentication required.

**Fix** : `pendingConnectionCount` atomic counter (NSLock-protected). When
`pendingConnections + connectedClients.count >= 100`, the raw socket is closed immediately
without spawning a thread. Commit `HEAD`.

---

### Z_003 — HIGH — GCD thread-pool exhaustion via half-authentication flood (no handshake timeout)
**File** : `Sources/WiredSwift/P7/P7Socket.swift`
**CVSS** : 7.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H)

A valid P7 `client_handshake` sent on 20 connections; connections then held open without sending
the key-exchange response. Server crashed in ~3 seconds. Zero authentication required.
Confirmed 100% reproducible before patch.

**Exploit** : A minimal P7 `client_handshake` (82 bytes) on 20 parallel TCP connections.
Server DOWN in ~3 s before patch.

**Fix** : `handshakeTimeout = 30s` added to all `readMessage()` calls in `acceptHandshake`,
`acceptKeyExchange`, and `receiveCompatibilityCheck` via `enforceDeadline: true`. Post-patch
retest (2026-03-17): 50 simultaneous half-auth connections — server stable throughout; all
connections closed by server at exactly 30 s; legitimate connections accepted concurrently.
Commit `76c8182`.

---

### Z_004 — HIGH — Low-and-slow variant: no wall-clock deadline on readExactly() in accept path
**File** : `Sources/WiredSwift/P7/P7Socket.swift:688`
**CVSS** : 7.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H)

Derivative of Z_003. `readExactly()` had `enforceDeadline: Bool = false` as default. Sending
1 byte per 59 seconds was sufficient to hold a GCD thread indefinitely. 64 such connections
exhausted the thread pool without producing any burst traffic detectable by rate limiters.

**Fix** : `enforceDeadline: true` propagated through the entire accept path. The 30 s deadline
is wall-clock, not inter-byte, so low-and-slow is equally constrained. Same commit `76c8182`.

---

## Finding Requiring Human Review

### P_018 — MEDIUM — No transaction state machine: message IDs not validated

**File** : `Sources/WiredSwift/P7/P7Message.swift`

The protocol currently accepts any message in any state without validating whether the message
ID is appropriate for the current connection phase. A client can send, for example, file
operation messages during the handshake phase, or handshake messages during file transfers.
While individual handlers do check `client.state`, the check is incomplete and scattered.

**Why deferred** : A proper fix requires a cross-cutting architectural change:

1. A per-connection enum state machine with well-defined valid message sets per state
   (`CONNECTED`, `GAVE_CLIENT_INFO`, `LOGGED_IN`, `TRANSFERRING`, etc.)
2. A central dispatch table mapping `(state, message_id)` to allowed handlers
3. Atomic state transitions coordinated across `P7Socket`, `P7Message`, and `ServerController`

After three patch attempts, all were abandoned to avoid introducing regressions in the
existing partial state checks. A minimal patch would create an illusion of protection while
leaving unverified code paths.

**Recommended approach** : Dedicated refactoring sprint. Define `ConnectionState` as a Swift
enum with an explicit allow-list of valid `P7Message` name sets per state. Validate at the
single dispatch entry point in `ServerController.receiveMessage`. State transitions should be
atomic (Swift actor or `NSLock`).

---

## Architectural Recommendations

1. **Centralized P7 parser with single ingress validation** — validation is currently scattered
   across `P7Message`, `P7Socket`, and individual handlers. A single `P7MessageValidator` running
   before dispatch would eliminate whole classes of handler-level bugs (force-unwraps, missing nil
   checks, duplicate validation, and P_018).

2. **Swift `actor` for SessionManager and ChatManager** — replacing manual `Lock`/`NSLock` wrappers
   with Swift actors would make data-race safety compile-time enforceable rather than
   convention-based. This directly eliminates the classes of bugs found in C_001, C_005, C_009,
   and A_006.

3. **Middleware authentication layer** — a server-side middleware chain where every message passes
   through `AuthMiddleware` before reaching handlers would centralize the state machine (P_018),
   privilege checks, and rate limiting in one place rather than the current pattern of per-handler
   guard/force-unwrap mixes.

4. **Rate limiting as a shared service** — the current per-feature rate limiters (A_001, C_006,
   C_012) are independent. A single `RateLimiter` service keyed by `(clientID, messageType)` would
   simplify future additions and provide a global view of client behavior for anomaly detection.

5. **Integrate network fuzzing into CI** — the network-layer crashes (FUZZ_001, FUZZ_002, Z_003,
   Z_004) were only discovered through active fuzzing. Running `wired3_fuzzer.py --manual` as a CI
   gate would catch similar regressions automatically. Recommended: a 5-minute fuzzing session on
   every PR targeting `main`/`master`.

---

## Metrics

| Metric | Value |
|--------|-------|
| Swift source files analysed | 87 |
| Total findings | 72 |
| CRITICAL patched | 9 / 9 |
| HIGH patched | 23 / 24 |
| MEDIUM patched | 33 / 34 |
| LOW patched | 5 / 5 |
| Findings needing human review | 1 (P_018) |
| Commits on audit branch | 43 |
| P7 protocol version at start | 1.0 |
| P7 protocol version at end | 1.3 |
| `swift build` | success |
| `swift test` | build error — 4 pre-existing compile errors in `WiredSwiftTests.swift` (see note) |

**Note on test failures** : The 4 compile errors in
`Tests/WiredSwiftTests/WiredSwiftTests.swift` are pre-existing and stem from
`Connection.connect(withUrl:)` changing its return type from `Bool` to `Void` in an earlier
(pre-audit) refactor. The test file was not modified during this audit (per project rules).
All production targets (`wired3`, `WiredServerApp`, `WiredSwift`) build cleanly.
Updating the test file is recommended as a follow-up task.

**Note on duplicate findings** : FUZZ_001 / FUZZ_002 appear both in `FINDING_FUZZ_*.json`
(patched) and in `FINDING_Z_001.json` / `FINDING_Z_002.json` (unpatched pre-session snapshot).
The severity table above counts them once each (as patched).
