import Foundation

public enum WiredProtocolSpec {
    public static func bundledSpecURL() -> URL? {
        // Bundle.module fatalErrors when the .bundle directory is missing (e.g.
        // when the wired3 binary is installed standalone without the app bundle).
        // Replicate the same search logic SPM generates but return nil instead
        // of crashing.
        //
        // Candidate reasoning (matches resource_bundle_accessor.swift generated
        // by this version of SPM):
        //   macOS swift test:  bundle is at Bundle.main.bundleURL/<name>.bundle
        //                      (inside xctest root, not in Contents/Resources/)
        //   macOS app:         bundle is at Bundle.main.resourceURL/<name>.bundle
        //   Linux swift test:  bundle is next to the test executable
        //   Standalone binary: same as Linux (executable parent dir), or nil
        let bundleName = "WiredSwift_WiredSwift"
        let candidates: [URL?] = [
            Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.executableURL?.deletingLastPathComponent()
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
