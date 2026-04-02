import Foundation

public enum WiredProtocolSpec {
    public static func bundledSpecURL() -> URL? {
        Bundle.module.url(forResource: "wired", withExtension: "xml")
    }

    public static func bundledSpec() -> P7Spec? {
        guard let url = bundledSpecURL() else {
            return nil
        }

        return P7Spec(withUrl: url)
    }
}
