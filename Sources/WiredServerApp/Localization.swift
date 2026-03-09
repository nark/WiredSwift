import Foundation

private enum AppLanguage: String {
    case en
    case fr
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
            .fr: Localizer.loadTable(for: .fr)
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
        let preferred = Bundle.main.preferredLocalizations + Locale.preferredLanguages
        for value in preferred {
            let languageCode = value
                .replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .first?
                .lowercased()

            if languageCode == AppLanguage.fr.rawValue {
                return .fr
            }
            if languageCode == AppLanguage.en.rawValue {
                return .en
            }
        }

        return .en
    }

    private static func loadTable(for language: AppLanguage) -> [String: String] {
        for bundle in candidateBundles() {
            guard
                let path = bundle.path(
                    forResource: "Localizable",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language.rawValue
                ),
                let table = NSDictionary(contentsOfFile: path) as? [String: String]
            else {
                continue
            }

            return table
        }

        return [:]
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main]

        if let resourceBundles = Bundle.main.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
            for url in resourceBundles {
                if let bundle = Bundle(url: url) {
                    bundles.append(bundle)
                }
            }
        }

        return bundles
    }
}

func L(_ key: String) -> String {
    Localizer.shared.localized(key)
}
