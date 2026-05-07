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
                if let table = parseStringsFile(at: url), !table.isEmpty {
                    return table
                }
            }
        }
        return [:]
    }

    // NSDictionary(contentsOf:) cannot parse UTF-8-without-BOM .strings files —
    // it silently returns nil. Read as UTF-8 and parse the "key" = "value"; format.
    private static func parseStringsFile(at url: URL) -> [String: String]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !content.isEmpty else { return nil }
        let pattern = try! NSRegularExpression(
            pattern: #"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#,
            options: [.anchorsMatchLines]
        )
        var result: [String: String] = [:]
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        for match in pattern.matches(in: content, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: content),
                  let valRange = Range(match.range(at: 2), in: content) else { continue }
            result[unescape(String(content[keyRange]))] = unescape(String(content[valRange]))
        }
        return result.isEmpty ? nil : result
    }

    private static func unescape(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\", s.index(after: i) < s.endIndex {
                let next = s.index(after: i)
                switch s[next] {
                case "n":  result.append("\n"); i = s.index(after: next); continue
                case "t":  result.append("\t"); i = s.index(after: next); continue
                case "r":  result.append("\r"); i = s.index(after: next); continue
                case "\"": result.append("\""); i = s.index(after: next); continue
                case "\\": result.append("\\"); i = s.index(after: next); continue
                default: break
                }
            }
            result.append(c)
            i = s.index(after: i)
        }
        return result
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
