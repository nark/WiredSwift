# Getting Started

## Prerequisites

- Swift 5.9+
- macOS or Linux

## Add Dependency

```swift
.package(url: "https://github.com/nark/WiredSwift.git", from: "3.0.0")
```

Then link the `WiredSwift` product to your target.

## Build And Test

```bash
swift build --product wired3
swift test
```

## Minimal Integration Flow

1. Create a ``Connection`` (or ``AsyncConnection`` for async/await code).
2. Configure client identity (`nick`, status, icon).
3. Connect to the server and authenticate.
4. Send and receive ``P7Message`` values.
5. Observe logs and server events during runtime.

## Where To Go Next

- Read <doc:ClientAPIOverview> for the main API choices.
- Read <doc:ProtocolAndSecurity> for crypto and trust model details.
