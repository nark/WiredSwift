import Foundation

public enum WiredProtocolSpec {
    public static func bundledSpecURL() -> URL? {
        // Bundle.module crashes with assertionFailure when the SPM .bundle directory
        // is missing from the app package. Search manually instead, then fall back to
        // Bundle.main.resourceURL where the build script also copies wired.xml directly.
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("WiredSwift_WiredSwift.bundle"),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("WiredSwift_WiredSwift.bundle"),
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
