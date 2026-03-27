# Connection Patterns

WiredSwift provides three ways to drive client messaging.

## 1) ``Connection``

Delegate-driven.

Use when you want explicit lifecycle control and delegate callbacks.

```swift
let connection = Connection(withSpec: spec, delegate: delegate)
let serverURL = Url(withString: "wired://guest@127.0.0.1:4871")
try connection.connect(withUrl: serverURL)
```

`Connection.connect(withUrl:)` throws on failure.

### Manual read loop mode

By default, `Connection` is interactive and dispatches incoming messages through delegates.

Set `interactive = false` before connecting if you want to run your own read loop.

```swift
connection.interactive = false
try connection.connect(withUrl: serverURL)

while connection.isConnected() {
    let message = try connection.readMessage()
    print(message.name ?? "<unknown>")
}
```

## 2) ``AsyncConnection``

Async/await.

Use in modern Swift concurrency codebases.

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

## 3) ``BlockConnection``

Callbacks.

Use when your architecture is callback-centric.

```swift
let blockConnection = BlockConnection(withSpec: spec, delegate: delegate)
try blockConnection.connect(withUrl: serverURL)

let message = P7Message(withName: "wired.board.get_boards", spec: spec)
blockConnection.send(
    message: message,
    progressBlock: { response in
        print("progress:", response.name ?? "<unknown>")
    },
    completionBlock: { final in
        print("done:", final?.name ?? "nil")
    }
)
```
