import Foundation

public enum WiredProtocolSpec {
    public static func bundledSpecURL() -> URL? {
        // Bundle.module crashes with fatalError when the .bundle directory is
        // missing (e.g. standalone wired3 binary without an app bundle alongside).
        // This replicates the same search but returns nil gracefully.
        let bundleName = "WiredSwift_WiredSwift"

        // macOS app bundle: SPM places the resource bundle inside Contents/Resources/.
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("\(bundleName).bundle")
            if let b = Bundle(path: candidate.path),
               let url = b.url(forResource: "wired", withExtension: "xml") {
                return url
            }
        }

        // macOS swift test: executable lives at xctest/Contents/MacOS/<name>,
        // so the build-output directory (where the bundle actually is) is 4 hops up.
        // Linux swift test: executable is directly in the build dir (1 hop up).
        // Walk up from the executable until we find the bundle or exhaust candidates.
        let execURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var searchDir = execURL
        for _ in 0..<5 {
            searchDir = searchDir.deletingLastPathComponent()
            let candidate = searchDir.appendingPathComponent("\(bundleName).bundle")
            if let b = Bundle(path: candidate.path),
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
