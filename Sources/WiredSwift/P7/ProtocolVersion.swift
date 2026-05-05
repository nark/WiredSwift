//
//  ProtocolVersion.swift
//  WiredSwift
//
//  Lightweight semver-style parser for the dotted version strings used on
//  the wire (`p7.handshake.version`, `p7.handshake.protocol.version`).
//

import Foundation

/// A `major.minor[.patch]` version, used for the P7 framing version and the
/// embedded Wired protocol version exchanged during the handshake.
///
/// Comparison is numeric per component (so `3.10 > 3.2`), which `String`
/// comparison does not give us.
public struct ProtocolVersion: Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"3"`, `"3.1"` or `"3.1.4"`. Missing components default to 0.
    /// Returns `nil` if the major component is missing or non-numeric.
    public init?(_ string: String) {
        let parts = string.split(separator: ".").map(String.init)
        guard let major = parts.first.flatMap(Int.init) else { return nil }
        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// Short form used on the wire: `major.minor` (drops a zero patch).
    public var wireFormat: String { "\(major).\(minor)" }

    public static func < (lhs: ProtocolVersion, rhs: ProtocolVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Two versions are wire-compatible if they share the same major component.
    /// Differences in the minor/patch components must be tolerated by readers
    /// (unknown fields/messages skipped, see COMPATIBILITY.md).
    public func isCompatible(with other: ProtocolVersion) -> Bool {
        major == other.major
    }

    /// The lower of two versions — used as the effective negotiated version
    /// when both peers share a major. Senders gate features on this.
    public static func negotiated(_ a: ProtocolVersion, _ b: ProtocolVersion) -> ProtocolVersion {
        a < b ? a : b
    }
}
