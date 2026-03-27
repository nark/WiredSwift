//
//  Chat.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import GRDB
import WiredSwift

/// A public chat room persisted in the `chats` SQLite table.
///
/// Chat rooms maintain an in-memory set of connected `Client` instances
/// protected by a reader/writer lock. Persistent metadata (topic, creation
/// info) is stored in the database; the client list is purely in-memory.
public class Chat: FetchableRecord, PersistableRecord {
    /// The GRDB table name for this model.
    public static let databaseTableName = "chats"

    // ── Champs DB ──────────────────────────────────────────────────────────
    public var id: Int64?
    /// Identifiant numérique du chat (UInt32 stocké en Int64 dans SQLite)
    public var chatID: UInt32
    public var name: String?
    public var topic: String
    public var topicNick: String
    public var topicTime: Date
    public var creationNick: String
    public var creationTime: Date

    // ── État in-memory (non persisté) ──────────────────────────────────────
    private var clients: [UInt32: Client] = [:]
    private var clientsLock: Lock = Lock()

    // MARK: - FetchableRecord
    /// Initialises a `Chat` from a GRDB database row.
    ///
    /// - Parameter row: The GRDB `Row` containing column values.
    public required init(row: Row) {
        id           = row["id"]
        chatID       = UInt32(truncatingIfNeeded: (row["chatID"] as Int64?) ?? 0)
        name         = row["name"]
        topic        = row["topic"] ?? ""
        topicNick    = row["topicNick"] ?? ""
        topicTime    = row["topicTime"] ?? Date()
        creationNick = row["creationNick"] ?? ""
        creationTime = row["creationTime"] ?? Date()
    }

    // MARK: - PersistableRecord
    /// Encodes this chat's persistent fields into a GRDB `PersistenceContainer`.
    ///
    /// - Parameter container: The container to write column values into.
    /// - Throws: Never; declared `throws` to satisfy the protocol.
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"]           = id
        container["chatID"]       = Int64(chatID)
        container["name"]         = name
        container["topic"]        = topic
        container["topicNick"]    = topicNick
        container["topicTime"]    = topicTime
        container["creationNick"] = creationNick
        container["creationTime"] = creationTime
    }

    /// Called by GRDB after an INSERT; captures the auto-assigned row identifier.
    ///
    /// - Parameter inserted: GRDB insertion result containing the new `rowID`.
    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Initialiseurs
    /// Creates a bare `Chat` with the given numeric chat identifier.
    ///
    /// - Parameter chatID: The Wired protocol chat ID (`UInt32`).
    public init(chatID: UInt32) {
        self.chatID       = chatID
        self.creationTime = Date()
        self.creationNick = ""
        self.topic        = ""
        self.topicNick    = ""
        self.topicTime    = Date()
    }

    /// Creates a named `Chat` room, recording the creating client as its creator.
    ///
    /// - Parameters:
    ///   - chatID: The Wired protocol chat ID.
    ///   - name: The human-readable room name.
    ///   - client: The `Client` that created the room, used to populate `creationNick`.
    public init(chatID: UInt32, name: String, client: Client?) {
        self.chatID       = chatID
        self.name         = name
        self.creationTime = Date()
        self.creationNick = client?.nick ?? ""
        self.topic        = ""
        self.topicNick    = ""
        self.topicTime    = Date()
    }

    // MARK: - Gestion des clients in-memory
    /// Returns the connected client with the given user ID, or `nil` if not present.
    ///
    /// - Parameter userID: The server-assigned numeric user identifier.
    /// - Returns: The matching `Client`, or `nil`.
    public func client(withID userID: UInt32) -> Client? {
        clientsLock.concurrentlyRead { self.clients[userID] }
    }

    /// Iterates over all clients currently in the room, calling `body` for each.
    ///
    /// The iteration is performed under a shared (concurrent-read) lock.
    ///
    /// - Parameter body: A closure called once per connected `Client`.
    public func withClients(_ body: (Client) -> Void) {
        clientsLock.concurrentlyRead {
            for (_, client) in clients { body(client) }
        }
    }

    /// Adds a client to this chat room's in-memory participant list.
    ///
    /// - Parameter client: The `Client` joining the room.
    public func addClient(_ client: Client) {
        clientsLock.exclusivelyWrite { self.clients[client.userID] = client }
    }

    /// Removes the client with the given user ID from this chat room.
    ///
    /// - Parameter userID: The server-assigned numeric identifier of the client to remove.
    public func removeClient(_ userID: UInt32) {
        clientsLock.exclusivelyWrite { self.clients[userID] = nil }
    }
}

/// An ephemeral private chat room visible only to explicitly invited clients.
///
/// Inherits persistence from `Chat` but adds an invitation list so that only
/// invited users may join. The invitation list is in-memory only and is not
/// stored in the database.
public class PrivateChat: Chat {
    private var invitedClients: [Client] = []
    private var invitedClientsLock: Lock = Lock()

    /// Records an outstanding invitation for the given client.
    ///
    /// - Parameter client: The `Client` being invited to the private chat.
    public func addInvitation(client: Client) {
        invitedClientsLock.exclusivelyWrite {
            self.invitedClients.append(client)
        }
    }

    /// Removes a pending invitation for the given client.
    ///
    /// - Parameter client: The `Client` whose invitation should be revoked.
    public func removeInvitation(client: Client) {
        invitedClientsLock.exclusivelyWrite {
            self.invitedClients.removeAll { (c) -> Bool in
                c.userID == client.userID
            }
        }
    }

    /// Returns whether the given client has a pending invitation to this private chat.
    ///
    /// - Parameter client: The `Client` to check.
    /// - Returns: `true` if the client has been invited and the invitation has not been removed.
    public func isInvited(client: Client) -> Bool {
        invitedClientsLock.concurrentlyRead {
            return self.invitedClients.contains(where: { $0.userID == client.userID })
        }
    }
}
