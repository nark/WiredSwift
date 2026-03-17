//
//  Chat.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import GRDB
import WiredSwift

public class Chat: FetchableRecord, PersistableRecord {
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

    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Initialiseurs
    public init(chatID: UInt32) {
        self.chatID       = chatID
        self.creationTime = Date()
        self.creationNick = ""
        self.topic        = ""
        self.topicNick    = ""
        self.topicTime    = Date()
    }

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
    public func client(withID userID: UInt32) -> Client? {
        clientsLock.concurrentlyRead { self.clients[userID] }
    }

    public func withClients(_ body: (Client) -> Void) {
        clientsLock.concurrentlyRead {
            for (_, client) in clients { body(client) }
        }
    }

    public func addClient(_ client: Client) {
        clientsLock.exclusivelyWrite { self.clients[client.userID] = client }
    }

    public func removeClient(_ userID: UInt32) {
        clientsLock.exclusivelyWrite { self.clients[userID] = nil }
    }
}



public class PrivateChat : Chat {
    private var invitedClients:[Client] = []
    private var invitedClientsLock: Lock = Lock()

    public func addInvitation(client:Client) {
        invitedClientsLock.exclusivelyWrite {
            self.invitedClients.append(client)
        }
    }


    public func removeInvitation(client:Client) {
        invitedClientsLock.exclusivelyWrite {
            self.invitedClients.removeAll { (c) -> Bool in
                c.userID == client.userID
            }
        }
    }


    public func isInvited(client:Client) -> Bool {
        invitedClientsLock.concurrentlyRead {
            for c in self.invitedClients {
                if c.userID == client.userID {
                    return true
                }
            }
            return false
        }
    }
}
