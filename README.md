# WiredSwift

Swift implementation of the Wired protocol, including:

- `WiredSwift`: reusable Swift library
- `wired3`: Wired 3 server daemon
- `WiredServerApp`: macOS GUI wrapper for local server installation and administration

Releases: https://github.com/nark/WiredSwift/releases

## Why This Repository Exists

This project serves three different audiences:

- Server operators who want to run a Wired 3 server on Linux or macOS
- App developers who want to integrate Wired protocol support in Swift
- Contributors who want to improve protocol/server/client internals

## Quick Start (Choose Your Path)

- [I want to run a server (User)](#for-users-running-a-server)
- [I want to integrate the library (Developer)](#for-developers-using-wiredswift)
- [I want to contribute to the project (Contributor)](#for-contributors)

---

## For Users (Running a Server)

### Option A: macOS with `WiredServerApp` (recommended on Mac)

`WiredServerApp` is a local admin UI around `wired3`.

Requirements:

- macOS 14+

Install from Releases:

1. Download `Wired-Server.app.zip` from [Releases](https://github.com/nark/WiredSwift/releases)
2. Unzip
3. Move `Wired Server.app` to `/Applications`
4. Launch the app
5. In **General** tab:
   - click **Install** to install `wired3`
   - click **Start** to run the server

Default runtime paths used by the app:

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

### Option B: Linux with `.deb` package

Requirements:

- Debian/Ubuntu-compatible distro
- Matching architecture (`amd64` or `arm64`)

Install:

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

### Option C: Linux with `.rpm` package

Requirements:

- RPM-based distro (Fedora, RHEL, Rocky, Alma, etc.)
- Matching architecture (`x86_64` or `aarch64`)

Install:

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

### Option D: Docker

You can run `wired3` in a container using the published image.

Pull:

```bash
docker pull ghcr.io/nark/wired3:<tag>
```

Run:

```bash
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

### Option E: Linux from source

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

### First Boot and Runtime Layout

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
  --root /var/lib/wired3/files \
  --spec /var/lib/wired3/wired.xml
```

### Systemd (Linux production baseline)

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
ExecStart=/usr/local/bin/wired3 --working-directory /var/lib/wired3 --config /var/lib/wired3/etc/config.ini --db /var/lib/wired3/wired3.db --root /var/lib/wired3/files --spec /var/lib/wired3/wired.xml
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

### Security Notes (Do This First)

At database bootstrap, default users are created:

- `admin` with initial password `admin`
- `guest` with empty password

You should immediately:

1. Change the admin password
2. Restrict network exposure (firewall, private interfaces)
3. Run the service as a dedicated non-root user

---

## For Developers (Using `WiredSwift`)

### Requirements

- Swift Package Manager
- Platform support declared in `Package.swift`: iOS 13+, macOS 13+

### Add Dependency

```swift
.package(name: "WiredSwift", url: "https://github.com/nark/WiredSwift", exact: "3.0.0+4")
```

### Unified Versioning (Library + Server)

This repository now uses a single release line for all targets (`WiredSwift`, `wired3`, `WiredServerApp`):

- Git tag: `v3.0+N` (example: `v3.0+4`)
- SwiftPM semantic version: `3.0.0+N` (example: `3.0.0+4`)

Use the right one for your goal:

- If you integrate `WiredSwift`, pin the matching SwiftPM version (`3.0.0+N`)
- If you want to build exactly the same server/app code as a GitHub release, checkout the matching git tag:

```bash
git checkout v3.0+4
swift build -c release --product wired3 -Xswiftc -DGRDBCUSTOMSQLITE
```

### Build Docker Image (Developer)

Local image build (single arch):

```bash
cd WiredSwift
docker buildx build \
  --platform linux/amd64 \
  -f Dockerfile \
  --target runtime \
  --build-arg WIRED_MARKETING_VERSION=3.0 \
  --build-arg WIRED_BUILD_NUMBER=12 \
  --build-arg WIRED_GIT_COMMIT=$(git rev-parse --short HEAD) \
  --load \
  -t wired3:dev .
```

Quick check:

```bash
docker run --rm --platform linux/amd64 wired3:dev --version
```

Multi-arch publish (example):

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile \
  --target runtime \
  --build-arg WIRED_MARKETING_VERSION=3.0 \
  --build-arg WIRED_BUILD_NUMBER=12 \
  --build-arg WIRED_GIT_COMMIT=$(git rev-parse --short HEAD) \
  --push \
  -t ghcr.io/nark/wired3:3.0-12 .
```

If you use the release automation, `Scripts/distribute.sh --prepare --phase docker` and `--upload --phase docker` generate/publish Docker tags and metadata automatically.

### Core Concepts

- `P7Spec`: protocol specification parser (`wired.xml`)
- `Url`: Wired URL (`wired://user:pass@host:port`)
- `Connection`: delegate-driven connection API
- `AsyncConnection`: async/await transaction-oriented API
- `BlockConnection`: callback-based transaction API

### Minimal `Connection` Example (Current API)

`Connection.connect` is `throws` (not `Bool`).

```swift
import Foundation
import WiredSwift

final class ClientDelegate: ConnectionDelegate {
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        print("recv:", message.name ?? "<unknown>")
    }

    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        print("error:", message.xml())
    }
}

let specURL = URL(string: "https://wired.read-write.fr/spec.xml")!
guard let spec = P7Spec(withUrl: specURL) else {
    fatalError("Cannot load protocol spec")
}

let delegate = ClientDelegate()
let connection = Connection(withSpec: spec, delegate: delegate)
connection.nick = "My Swift Client"
connection.status = "Online"

let serverURL = Url(withString: "wired://guest@127.0.0.1:4871")

try connection.connect(withUrl: serverURL)
_ = connection.joinChat(chatID: 1)
```

### Manual (Non-Interactive) Mode

By default, `Connection` is interactive (`interactive = true`) and dispatches incoming messages through delegates.

For explicit read loops:

```swift
connection.interactive = false
try connection.connect(withUrl: serverURL)

while connection.isConnected() {
    let message = try connection.readMessage()
    print(message.name ?? "<unknown>")
}
```

### `AsyncConnection` (async/await)

`AsyncConnection` adds transaction streams tied to `wired.transaction`.

Single-response style:

```swift
let asyncConnection = AsyncConnection(withSpec: spec, delegate: delegate)
try asyncConnection.connect(withUrl: serverURL)

let msg = P7Message(withName: "wired.board.get_boards", spec: spec)
let first = try await asyncConnection.sendAsync(msg)
print(first?.name ?? "no response")
```

Multi-response stream style:

```swift
let msg = P7Message(withName: "wired.board.get_boards", spec: spec)
let stream = try asyncConnection.sendAndWaitMany(msg)

for try await response in stream {
    print("stream:", response.name ?? "<unknown>")
}
```

### `BlockConnection` (callbacks)

```swift
let blockConnection = BlockConnection(withSpec: spec, delegate: delegate)
try blockConnection.connect(withUrl: serverURL)

let message = P7Message(withName: "wired.board.get_boards", spec: spec)
blockConnection.send(message: message, progressBlock: { response in
    print("progress:", response.name ?? "<unknown>")
}, completionBlock: { final in
    print("done:", final?.name ?? "nil")
})
```

### Logging

```swift
Logger.setMaxLevel(.ERROR)
Logger.removeDestination(.Stdout)
```

### Local Dev Commands

```bash
swift build -v
swift run wired3 --working-directory ./run
```

Build macOS wrapper app bundle:

```bash
./Scripts/build-wired-server-app.sh release
```

Output artifacts:

- `dist/Wired Server.app`
- `dist/Wired-Server.app.zip`
- `dist/wired3`
- `dist/wired3.zip`

---

## For Contributors

### Local Setup

```bash
git clone https://github.com/nark/WiredSwift.git
cd WiredSwift
swift build -v
```

### Project Layout

- `Sources/WiredSwift`: library implementation
- `Sources/wired3`: server daemon
- `Sources/WiredServerApp`: macOS wrapper UI
- `Scripts/debian`: Debian packaging assets (`control`, maintainer scripts, systemd unit)
- `Scripts/build-wired-server-app.sh`: macOS app packaging script
- `.github/workflows/build-linux-deb-packages.yml`: CI workflow for amd64/arm64 `.deb` artifacts

### Current Build/Test Reality

As of March 6, 2026:

- `swift build -c release --product wired3` succeeds locally
- Linux CI build command: `swift build -c release --product wired3 -Xswiftc -DGRDBCUSTOMSQLITE`
- Some tests still target an older `Connection.connect` API shape and currently fail to compile

If you submit a PR touching networking APIs, include test updates when signatures change.

### Contribution Priorities

- Protocol correctness and compatibility
- Socket I/O reliability
- Multi-thread/concurrency robustness
- Regression-resistant test coverage
- Server operational stability

### Typical Contribution Workflow

1. Open an issue describing bug/feature scope
2. Submit a focused PR
3. Add/update tests and docs for behavior changes
4. Include migration notes if public API changed

---

## License

BSD license. See [LICENSE](LICENSE).

- Copyright (c) 2003-2009 Axel Andersson
- Copyright (c) 2011-2020 Rafaël Warnault
