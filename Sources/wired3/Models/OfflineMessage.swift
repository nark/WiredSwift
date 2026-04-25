//
//  OfflineMessage.swift
//  wired3
//

import GRDB
import Foundation

struct OfflineMessage: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "offline_messages"

    var id: Int64?
    var senderLogin: String
    var recipientLogin: String
    var body: String
    var sentAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderLogin    = "sender_login"
        case recipientLogin = "recipient_login"
        case body
        case sentAt         = "sent_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
