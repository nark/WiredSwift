//
//  Config.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 28/04/2021.
//

import Foundation

/// A simple INI-style configuration file reader and writer.
///
/// The file format uses `[section]` headers followed by `key = value` lines.
/// Values are accessed and mutated via the `subscript(section:key:)` subscript,
/// which automatically persists changes back to disk.
public class Config {
    private var config: [String: [String: Any]] = [:]
    private var path: String

    /// Creates a `Config` instance pointing at the given file path.
    ///
    /// The file is not read until `load()` is called.
    ///
    /// - Parameter path: Absolute path to the INI-style configuration file.
    public init(withPath path: String) {
        self.path = path
    }

    /// Reads the configuration file from disk and populates the in-memory store.
    ///
    /// - Returns: `true` on success; `false` if the file cannot be read or does not exist.
    public func load() -> Bool {
        do {
            let contents = try String(contentsOfFile: path)
            let lines = contents.split(separator: "\n")
            var section: String?

            for line in lines {
                if line.isEmpty {
                    continue
                }

                // current section
                if line.hasPrefix("[") && line.hasSuffix("]") {
                    section = String(line)

                    if config[section!] == nil {
                        config[section!] = [:]
                    }

                    continue
                }

                if section != nil {
                    let comps = line.split(separator: "=")

                    if comps.count == 2 {
                        config[section!]![comps[0].trimmingCharacters(in: .whitespaces)] = comps[1].trimmingCharacters(in: .whitespaces)
                    } else if comps.count == 1 {
                        config[section!]![comps[0].trimmingCharacters(in: .whitespaces)] = nil
                    } else {
                        Logger.warning("Invalid entry in config file \(path)")
                    }
                }
            }
        } catch let error {
            Logger.error("Cannot load config file \(path) \(error)")
            return false
        }

        return true
    }

    /// Serialises the in-memory store and writes it atomically to the file on disk.
    ///
    /// - Returns: `true` on success; `false` if the write fails.
    @discardableResult
    public func save() -> Bool {
        var string: String = ""

        for (section, dict) in self.config {
            string += section + "\n"
            for (k, v) in dict {
                string += "\(k) = \(v)" + "\n"
            }
            string += "\n"
        }

        do {
            // Write in place so service-managed configs under /etc remain editable by
            // the daemon when the file itself is writable but the directory is not.
            try string.write(to: URL(fileURLWithPath: self.path), atomically: false, encoding: .utf8)
        } catch let error {
            Logger.error("Cannot save config file \(path) \(error)")
            return false
        }

        return true
    }

    /// Accesses the value for `key` within `section`.
    ///
    /// Setting a value writes the updated config back to disk immediately.
    ///
    /// - Parameters:
    ///   - section: The section name without brackets, e.g. `"server"`.
    ///   - key: The key within that section.
    public subscript(section: String, key: String) -> Any? {
        get {
            return config["[\(section)]"]?[key]
        }
        set(newValue) {
            let sectionKey = "[\(section)]"

            if config[sectionKey] == nil {
                config[sectionKey] = [:]
            }

            config[sectionKey]![key] = newValue

            self.save()
        }
    }
}
