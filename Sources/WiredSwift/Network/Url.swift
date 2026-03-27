//
//  Url.swift
//  Wired 3
//
//  Created by Rafael Warnault on 18/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation

/// A parsed Wired connection URL of the form `wired://[login[:password]@]host[:port][/path]`.
///
/// Pass a URL string to `init(withString:)`; the individual components are then available
/// as typed properties with sensible defaults (login = `"guest"`, port = `4871`).
public class Url: NSObject {
    public var base: String     = ""
    public var scheme: String   = Wired.wiredScheme
    public var login: String    = "guest"
    public var password: String = ""
    public var hostname: String = ""
    public var port: Int        = Wired.wiredPort

    /// Parses a Wired URL string and populates all component properties.
    ///
    /// - Parameter baseString: A URL string such as `"wired://alice:secret@example.com:4871"`.
    public init(withString baseString: String) {
        super.init()

        self.base = baseString

        self.decompose()
    }

    /// Returns a canonical `wired://hostname:port` string for this URL (login and password are omitted).
    public func urlString() -> String {
        return "wired://\(self.hostname):\(self.port)"
    }

    private func decompose() {
        if let u = URL(string: self.base) {
            self.hostname   = u.host!
            self.port       = u.port ?? Wired.wiredPort
            self.login      = u.user ?? "guest"
            self.password   = u.password ?? ""
            self.scheme     = u.scheme!
        } else {
            Logger.error("ERROR: Invalid URL")
        }
    }
}
