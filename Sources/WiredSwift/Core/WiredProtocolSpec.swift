import Foundation

public enum WiredProtocolSpec {
    public static func bundledSpecURL() -> URL? {
        // Bundle.module crashes with assertionFailure when the SPM .bundle directory
        // is missing from the app package. Search manually instead.
        //
        // Path reasoning:
        //  - Production app:    Bundle.main.resourceURL / Contents/Resources
        //  - Linux swift test:  executable is in .build/debug/, bundle is beside it
        //  - macOS swift test:  Bundle.main.bundleURL is the .xctest package;
        //                       its parent directory is .build/debug/ where the
        //                       WiredSwift_WiredSwift.bundle actually lives
        let bundleName = "WiredSwift_WiredSwift"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("\(bundleName).bundle"),
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
