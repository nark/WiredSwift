import Foundation

public enum ConfigFileDefaults {
    @discardableResult
    public static func ensureStrictIdentitySetting(at path: String, defaultValue: String = "yes") -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }

        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }

        let newline = contents.contains("\r\n") ? "\r\n" : "\n"
        var lines = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if newline == "\r\n" {
            lines = lines.map { line in
                line.hasSuffix("\r") ? String(line.dropLast()) : line
            }
        }

        var inSecuritySection = false
        var securitySectionIndex: Int?
        var nextSectionIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let isSecuritySection = trimmed.caseInsensitiveCompare("[security]") == .orderedSame
                if inSecuritySection && !isSecuritySection {
                    nextSectionIndex = index
                    break
                }

                inSecuritySection = isSecuritySection
                if isSecuritySection && securitySectionIndex == nil {
                    securitySectionIndex = index
                }
                continue
            }

            guard inSecuritySection else { continue }
            if trimmed.hasPrefix(";") || trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }

            let key = trimmed
                .split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if key == "strict_identity" {
                return false
            }
        }

        let insertLine = "strict_identity = \(defaultValue)"
        let trailingEmptyCount = lines.reversed().prefix { $0.isEmpty }.count
        let contentEndIndex = lines.count - trailingEmptyCount

        if securitySectionIndex != nil {
            let insertIndex = nextSectionIndex ?? contentEndIndex
            lines.insert(insertLine, at: insertIndex)
        } else {
            if contentEndIndex > 0 {
                lines.removeLast(trailingEmptyCount)
                if lines.last?.isEmpty == false {
                    lines.append("")
                }
            }
            lines.append("[security]")
            lines.append(insertLine)
        }

        let updatedContents = lines.joined(separator: newline)
        do {
            try updatedContents.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
