import Foundation

// Mirrors what SPM generates in Bundle.module: a class whose bundle lookup
// locates the WiredSwift resource bundle regardless of whether the caller is
// an app, a test target, or a standalone daemon binary.
private final class _BundleFinder: NSObject {}

public enum WiredProtocolSpec {
    public static func bundledSpecURL() -> URL? {
        // Bundle.module fatalErrors when the .bundle directory is missing (e.g.
        // when the wired3 binary is installed standalone without the app bundle).
        // Search manually with the same candidates SPM uses, but return nil on
        // failure instead of crashing.
        let bundleName = "WiredSwift_WiredSwift"
        let candidates: [URL?] = [
            // App bundle / xctest Contents/Resources/ (macOS app and swift test)
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            // Class bundle — mirrors SPM's Bundle(for: BundleFinder.self) candidate;
            // on macOS swift test this resolves the xctest's resource directory
            // where SPM embeds the package resource bundle.
            Bundle(for: _BundleFinder.self).resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            // Executable's directory (Linux swift test, standalone binary)
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("\(bundleName).bundle"),
            // xctest bundle parent directory (fallback for macOS swift test)
            Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("\(bundleName).bundle"),
        ]
        for case let bundleURL? in candidates {
            if let b = Bundle(url: bundleURL),
               let url = b.url(forResource: "wired", withExtension: "xml") {
                return url
            }
        }
        return Bundle.main.url(forResource: "wired", withExtension: "xml")
    }

    public static func bundledSpec() -> P7Spec? {
        guard let url = bundledSpecURL() else {
            return nil
        }

        return P7Spec(withUrl: url)
    }
}
