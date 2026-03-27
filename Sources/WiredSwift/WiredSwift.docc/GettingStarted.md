# Getting Started

## Requirements

- Swift Package Manager
- Platform support declared in this package: iOS 13+, macOS 13+

## Add The Dependency

```swift
.package(url: "https://github.com/nark/WiredSwift.git", from: "3.0.0")
```

Then add `WiredSwift` to your target dependencies.

## Version Mapping

This repository uses one release line across `WiredSwift`, `wired3`, and `WiredServerApp`.

- Git tag format: `v3.0+N` (example: `v3.0+4`)
- SwiftPM semantic version: `3.0.0+N` (example: `3.0.0+4`)

If you need an exact release build match, checkout the matching Git tag first.

```bash
git checkout v3.0+4
swift build -c release --product wired3 -Xswiftc -DGRDBCUSTOMSQLITE
```

## Load The Protocol Spec

Use a local `wired.xml` file and initialize ``P7Spec`` with its path.

```swift
let spec = P7Spec(withPath: "/absolute/path/to/wired.xml")
```

## First Connection Example

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

let spec = P7Spec(withPath: "/absolute/path/to/wired.xml")
let delegate = ClientDelegate()

let connection = Connection(withSpec: spec, delegate: delegate)
connection.nick = "My Swift Client"
connection.status = "Online"

let serverURL = Url(withString: "wired://guest@127.0.0.1:4871")
try connection.connect(withUrl: serverURL)
_ = connection.joinChat(chatID: 1)
```

## Next Step

Read <doc:ConnectionPatterns> to choose between delegate, async/await, and callback styles.
