//
//  BanListController.swift
//  wired3
//

import Foundation
import GRDB

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum BanListError: Error {
    case invalidPattern
    case invalidExpirationDate
    case alreadyExists
    case notFound
}

struct IPAddress {
    enum Family {
        case ipv4
        case ipv6
    }

    let family: Family
    let bytes: [UInt8]

    init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var ipv4 = in_addr()
        if trimmed.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            let length = MemoryLayout<in_addr>.size
            let bytes = withUnsafeBytes(of: &ipv4) { Array($0.prefix(length)) }
            self.family = .ipv4
            self.bytes = bytes
            return
        }

        var ipv6 = in6_addr()
        if trimmed.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let length = MemoryLayout<in6_addr>.size
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0.prefix(length)) }
            self.family = .ipv6
            self.bytes = bytes
            return
        }

        return nil
    }
}

enum BanPattern {
    case exact(IPAddress)
    case wildcardIPv4([UInt8?])
    case cidr(IPAddress, Int)
    case netmaskIPv4(base: [UInt8], mask: [UInt8])

    static func parse(_ raw: String) -> BanPattern? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("*") {
            return parseWildcardIPv4(trimmed)
        }

        if let slashIndex = trimmed.lastIndex(of: "/") {
            let lhs = String(trimmed[..<slashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = String(trimmed[trimmed.index(after: slashIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let base = IPAddress(string: lhs), !rhs.isEmpty else { return nil }

            if let prefixLength = Int(rhs) {
                switch base.family {
                case .ipv4:
                    guard (0...32).contains(prefixLength) else { return nil }
                case .ipv6:
                    guard (0...128).contains(prefixLength) else { return nil }
                }

                return .cidr(base, prefixLength)
            }

            guard base.family == .ipv4, let mask = IPAddress(string: rhs), mask.family == .ipv4 else {
                return nil
            }

            return .netmaskIPv4(base: base.bytes, mask: mask.bytes)
        }

        guard let address = IPAddress(string: trimmed) else { return nil }
        return .exact(address)
    }

    func matches(ipAddress: String) -> Bool {
        guard let candidate = IPAddress(string: ipAddress) else { return false }

        switch self {
        case .exact(let address):
            return address.family == candidate.family && address.bytes == candidate.bytes

        case .wildcardIPv4(let octets):
            guard candidate.family == .ipv4, candidate.bytes.count == 4 else { return false }

            for (index, octet) in octets.enumerated() {
                if let octet, candidate.bytes[index] != octet {
                    return false
                }
            }

            return true

        case .cidr(let network, let prefixLength):
            guard network.family == candidate.family, network.bytes.count == candidate.bytes.count else {
                return false
            }

            return Self.prefixMatch(lhs: network.bytes, rhs: candidate.bytes, prefixLength: prefixLength)

        case .netmaskIPv4(let base, let mask):
            guard candidate.family == .ipv4, base.count == 4, mask.count == 4, candidate.bytes.count == 4 else {
                return false
            }

            for index in 0..<4 {
                if (candidate.bytes[index] & mask[index]) != (base[index] & mask[index]) {
                    return false
                }
            }

            return true
        }
    }

    private static func prefixMatch(lhs: [UInt8], rhs: [UInt8], prefixLength: Int) -> Bool {
        let fullBytes = prefixLength / 8
        let remainingBits = prefixLength % 8

        if fullBytes > 0 && lhs.prefix(fullBytes) != rhs.prefix(fullBytes) {
            return false
        }

        guard remainingBits > 0 else { return true }
        let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - remainingBits))
        return (lhs[fullBytes] & mask) == (rhs[fullBytes] & mask)
    }

    private static func parseWildcardIPv4(_ raw: String) -> BanPattern? {
        let segments = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...4).contains(segments.count) else { return nil }

        var octets = [UInt8?](repeating: nil, count: 4)
        var sawWildcard = false

        for (index, segment) in segments.enumerated() {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "*" {
                sawWildcard = true
                continue
            }

            guard !sawWildcard, let value = UInt8(trimmed) else { return nil }
            octets[index] = value
        }

        return .wildcardIPv4(octets)
    }
}

public final class BanListController {
    private let databaseController: DatabaseController

    init(databaseController: DatabaseController) {
        self.databaseController = databaseController
    }

    func getBan(forIPAddress ipAddress: String) throws -> BanEntry? {
        try databaseController.dbQueue.write { db in
            try cleanupExpiredBans(in: db)

            let bans = try BanEntry
                .order(BanEntry.Columns.ipPattern.asc)
                .fetchAll(db)

            for ban in bans {
                guard let pattern = BanPattern.parse(ban.ipPattern), pattern.matches(ipAddress: ipAddress) else {
                    continue
                }

                return ban
            }

            return nil
        }
    }

    func listBans() throws -> [BanEntry] {
        try databaseController.dbQueue.write { db in
            try cleanupExpiredBans(in: db)

            return try BanEntry
                .order(BanEntry.Columns.expirationDate.asc, BanEntry.Columns.ipPattern.asc)
                .fetchAll(db)
        }
    }

    func addBan(ipPattern rawPattern: String, expirationDate: Date?) throws -> BanEntry {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BanPattern.parse(pattern) != nil else {
            throw BanListError.invalidPattern
        }

        if let expirationDate, expirationDate <= Date() {
            throw BanListError.invalidExpirationDate
        }

        return try databaseController.dbQueue.write { db in
            try cleanupExpiredBans(in: db)

            let existing = try BanEntry
                .filter(BanEntry.Columns.ipPattern == pattern)
                .fetchOne(db)

            guard existing == nil else {
                throw BanListError.alreadyExists
            }

            let ban = BanEntry(ipPattern: pattern, expirationDate: expirationDate)
            try ban.insert(db)
            return ban
        }
    }

    func deleteBan(ipPattern rawPattern: String, expirationDate: Date?) throws {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            throw BanListError.invalidPattern
        }

        try databaseController.dbQueue.write { db in
            try cleanupExpiredBans(in: db)

            guard let existing = try BanEntry
                .filter(BanEntry.Columns.ipPattern == pattern)
                .fetchOne(db) else {
                throw BanListError.notFound
            }

            if let expirationDate {
                guard existing.expirationDate == expirationDate else {
                    throw BanListError.notFound
                }
            }

            try existing.delete(db)
        }
    }

    @discardableResult
    func cleanupExpiredBans() throws -> Int {
        try databaseController.dbQueue.write { db in
            try cleanupExpiredBans(in: db)
        }
    }

    @discardableResult
    private func cleanupExpiredBans(in db: Database) throws -> Int {
        try BanEntry
            .filter(BanEntry.Columns.expirationDate != nil && BanEntry.Columns.expirationDate <= Date())
            .deleteAll(db)
    }
}
