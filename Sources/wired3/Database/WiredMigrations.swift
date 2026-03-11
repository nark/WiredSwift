//
//  WiredMigrations.swift
//  wired3
//

import GRDB

enum WiredMigrations {

    static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial_schema") { db in
            try WiredMigrations.v1(db)
        }
        // Futures migrations :
        // migrator.registerMigration("v2_add_column_X") { db in ... }
    }

    // swiftlint:disable:next function_body_length
    static func v1(_ db: Database) throws {

        // ── users ───────────────────────────────────────────────────────────
        try db.create(table: "users", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("username", .text).notNull().unique()
            t.column("password", .text).notNull()
            t.column("full_name", .text)
            t.column("identity", .text).unique()
            t.column("comment", .text)
            t.column("creation_time", .datetime)
            t.column("modification_time", .datetime)
            t.column("login_time", .datetime)
            t.column("edited_by", .text)
            t.column("downloads", .integer)
            t.column("download_transferred", .integer)
            t.column("uploads", .integer)
            t.column("upload_transferred", .integer)
            t.column("group", .text)
            t.column("groups", .text)
            t.column("color", .text)
            t.column("files", .text)
            t.column("offline_public_key", .blob)
            t.column("offline_key_id", .text)
            t.column("offline_crypto", .text)
        }

        // ── groups ──────────────────────────────────────────────────────────
        try db.create(table: "groups", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull().unique()
            t.column("color", .text)
        }

        // ── user_privileges ─────────────────────────────────────────────────
        try db.create(table: "user_privileges", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("value", .boolean).notNull()
            t.column("user_id", .integer).notNull()
                .references("users", onDelete: .cascade)
            t.uniqueKey(["name", "user_id"])
        }

        // ── group_privileges ────────────────────────────────────────────────
        try db.create(table: "group_privileges", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("value", .boolean).notNull()
            t.column("group_id", .integer).notNull()
                .references("groups", onDelete: .cascade)
            t.uniqueKey(["name", "group_id"])
        }

        // ── chats ───────────────────────────────────────────────────────────
        try db.create(table: "chats", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("chatID", .integer).notNull()
            t.column("name", .text)
            t.column("topic", .text).notNull()
            t.column("topicNick", .text).notNull()
            t.column("topicTime", .datetime).notNull()
            t.column("creationNick", .text).notNull()
            t.column("creationTime", .datetime).notNull()
        }

        // ── index ───────────────────────────────────────────────────────────
        try db.create(table: "index", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("virtual_path", .text).notNull()
            t.column("real_path", .text).notNull()
            t.column("alias", .boolean).notNull()
        }

        // ── offline_messages ────────────────────────────────────────────────
        try db.create(table: "offline_messages", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()   // UUID stocké en texte
            t.column("sender_identity", .text).notNull()
            t.column("recipient_identity", .text).notNull()
            t.column("ciphertext", .blob).notNull()
            t.column("nonce", .blob).notNull()
            t.column("wrapped_key_recipient", .blob).notNull()
            t.column("wrapped_key_sender", .blob)
            t.column("recipient_key_id", .text)
            t.column("created_at", .datetime).notNull()
            t.column("expires_at", .datetime).notNull()
            t.column("delivered_at", .datetime)
            t.column("acked_at", .datetime)
        }
        try db.create(
            index: "offline_messages_recipient_index",
            on: "offline_messages",
            columns: ["recipient_identity"],
            ifNotExists: true
        )
        try db.create(
            index: "offline_messages_expires_index",
            on: "offline_messages",
            columns: ["expires_at"],
            ifNotExists: true
        )
    }
}
