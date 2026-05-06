import Foundation

/// Resolves the canonical `wired.xml` location from the test source tree.
///
/// `WiredProtocolSpec.bundledSpec()` deliberately returns nil rather than
/// crashing when the SPM resource bundle cannot be located, so tests that
/// need the spec resolve it from `#filePath` instead — robust across
/// macOS xctest and Linux SPM regardless of how SPM exposes resources.
enum TestResources {
    static let specURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/WiredSwift/Resources/wired.xml")
}
