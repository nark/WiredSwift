import Foundation

private enum AppLanguage: String {
    case en
    case fr
    case de
}

private final class Localizer {
    static let shared = Localizer()

    private let fallbackLanguage: AppLanguage = .en
    private let selectedLanguage: AppLanguage
    private let tableByLanguage: [AppLanguage: [String: String]]

    private init() {
        let selected = Localizer.resolveLanguage()
        self.selectedLanguage = selected
        self.tableByLanguage = [
            .en: Localizer.loadTable(for: .en),
            .fr: Localizer.loadTable(for: .fr),
            .de: Localizer.loadTable(for: .de)
        ]
    }

    func localized(_ key: String) -> String {
        if let localized = tableByLanguage[selectedLanguage]?[key] {
            return localized
        }
        if let localized = tableByLanguage[fallbackLanguage]?[key] {
            return localized
        }
        return key
    }

    private static func resolveLanguage() -> AppLanguage {
        for value in Locale.preferredLanguages {
            let languageCode = value
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first?
                .lowercased()

            if languageCode == AppLanguage.de.rawValue { return .de }
            if languageCode == AppLanguage.fr.rawValue { return .fr }
            if languageCode == AppLanguage.en.rawValue { return .en }
        }
        return .en
    }

    private static func loadTable(for language: AppLanguage) -> [String: String] {
        let lproj = "\(language.rawValue).lproj"
        let filename = "Localizable.strings"
        for bundle in candidateBundles() {
            // Try both resourceURL and bundleURL: SPM flat bundles expose
            // resources at bundleURL, app bundles at resourceURL (Contents/Resources/).
            for root in [bundle.resourceURL, bundle.bundleURL].compactMap({ $0 }) {
                let url = root.appendingPathComponent(lproj).appendingPathComponent(filename)
                if let table = NSDictionary(contentsOf: url) as? [String: String] {
                    return table
                }
            }
        }
        return [:]
    }

    private static func candidateBundles() -> [Bundle] {
        // Bundle.module calls assertionFailure when the SPM resource bundle is absent
        // from the app package, crashing at startup. Search for it manually instead
        // so we can fall back to Bundle.main without a crash.
        // Search roots mirror the 6 paths that SPM's generated Bundle.module checks.
        let spmBundleName = "WiredSwift_WiredServerApp"
        let finder = Localizer.self
        let roots: [URL?] = [
            Bundle.main.resourceURL,
            Bundle(for: finder).resourceURL,
            Bundle.main.resourceURL?
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources"),
            Bundle(for: finder).resourceURL?
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources"),
            Bundle(for: finder).resourceURL?
                .deletingLastPathComponent()
                .appendingPathComponent("Resources"),
            Bundle(for: finder).resourceURL?
                .deletingLastPathComponent(),
        ]
        for root in roots.compactMap({ $0 }) {
            if let b = Bundle(url: root.appendingPathComponent("\(spmBundleName).bundle")) {
                return [b, .main]
            }
        }
        return [.main]
    }
}

func L(_ key: String) -> String {
    Localizer.shared.localized(key)
}
