//
//  ServerInfo.swift
//  Wired 3
//
//  Created by Rafael Warnault on 20/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation

/// Describes a remote Wired server, populated from the `wired.server_info`
/// message received during connection handshake.
public class ServerInfo {
    public var applicationName: String = ""
    public var applicationVersion: String = ""
    public var applicationBuild: String = ""

    public var osName: String = ""
    public var osVersion: String = ""
    public var arch: String = ""

    public var supportRSRC: Bool = false
    public var serverName: String = ""
    public var serverDescription: String = ""
    public var serverBanner: Data = Data()

    public var startTime: Date = Date()
    public var filesCount: UInt64 = 0
    public var filesSize: UInt64 = 0

    private var message: P7Message

    /// A formatted string combining the application version and build number,
    /// e.g. `"3.0.1 (500)"`.
    public var serverVersion: String {
        return "\(applicationVersion) (\(applicationBuild))"
    }

    /// A formatted string combining OS name, version and CPU architecture,
    /// e.g. `"macOS 14.0 (arm64)"`.
    public var hostInfo: String {
        return "\(osName) \(osVersion) (\(arch))"
    }

    /// Creates a `ServerInfo` by extracting all `wired.info.*` fields from
    /// the supplied `wired.server_info` P7 message.
    ///
    /// - Parameter message: The decoded `wired.server_info` P7 message.
    public init(message: P7Message) {
        self.message = message

        if let v = message.string(forField: "wired.info.application.name") {
            self.applicationName = v
        }

        if let v = message.string(forField: "wired.info.application.version") {
            self.applicationVersion = v
        }

        if let v = message.string(forField: "wired.info.application.build") {
            self.applicationBuild = v
        }

        if let v = message.string(forField: "wired.info.os.name") {
            self.osName = v
        }

        if let v = message.string(forField: "wired.info.os.version") {
            self.osVersion = v
        }

        if let v = message.string(forField: "wired.info.arch") {
            self.arch = v
        }

        if let v = message.bool(forField: "wired.info.supports_rsrc") {
            self.supportRSRC = v
        }

        if let v = message.string(forField: "wired.info.name") {
            self.serverName = v
        }

        if let v = message.string(forField: "wired.info.description") {
            self.serverDescription = v
        }

        if let v = message.data(forField: "wired.info.banner") {
            self.serverBanner = v
        }

        if let v = message.date(forField: "wired.info.start_time") {
            self.startTime = v
        }

        if let v = message.uint64(forField: "wired.info.files.count") {
            self.filesCount = v
        }

        if let v = message.uint64(forField: "wired.info.files.size") {
            self.filesSize = v
        }
    }
}
