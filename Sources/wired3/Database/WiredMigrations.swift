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
        migrator.registerMigration("v2_fts5_file_search") { db in
            try WiredMigrations.v2(db)
        }
        migrator.registerMigration("v3_add_search_files_privilege") { db in
            try WiredMigrations.v3(db)
        }
        migrator.registerMigration("v4_add_password_salt") { db in
            try WiredMigrations.v4(db)
        }
        migrator.registerMigration("v5_add_search_boards_privilege") { db in
            try WiredMigrations.v5(db)
        }
        migrator.registerMigration("v6_banlist") { db in
            try WiredMigrations.v6(db)
        }
        migrator.registerMigration("v7_events") { db in
            try WiredMigrations.v7(db)
        }
        migrator.registerMigration("v8_add_sync_privileges") { db in
            try WiredMigrations.v8(db)
        }
    }

    static func v2(_ db: Database) throws {
        // Add generation_id to "index" table for race-free full rebuilds.
        // Each rebuild stamps a new generation; old-generation rows are deleted
        // only after all new rows are inserted, so readers always see valid data.
        try db.alter(table: "index") { t in
            t.add(column: "generation_id", .integer).notNull().defaults(to: 0)
        }

        // FTS5 virtual table backed by the "index" content table.
        // Tokenizer: unicode61 with diacritic removal for accent-insensitive search.
        // Will fail gracefully on SQLite builds without FTS5 (e.g. some Linux distros).
        do {
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS file_search
                USING fts5(
                    name,
                    virtual_path,
                    content='index',
                    content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                )
            """)

            // Populate FTS5 from existing rows.
            try db.execute(sql: """
                INSERT INTO file_search(rowid, name, virtual_path)
                SELECT id, name, virtual_path FROM "index"
            """)

            // Synchronisation triggers: keep FTS5 in sync with the "index" table.
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS index_ai
                AFTER INSERT ON "index" BEGIN
                    INSERT INTO file_search(rowid, name, virtual_path)
                    VALUES (new.id, new.name, new.virtual_path);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS index_ad
                AFTER DELETE ON "index" BEGIN
                    INSERT INTO file_search(file_search, rowid, name, virtual_path)
                    VALUES ('delete', old.id, old.name, old.virtual_path);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS index_au
                AFTER UPDATE ON "index" BEGIN
                    INSERT INTO file_search(file_search, rowid, name, virtual_path)
                    VALUES ('delete', old.id, old.name, old.virtual_path);
                    INSERT INTO file_search(rowid, name, virtual_path)
                    VALUES (new.id, new.name, new.virtual_path);
                END
            """)
        } catch {
            // FTS5 not compiled into this SQLite build.
            // IndexController detects this at runtime and falls back to LIKE-based search.
            print("[WiredMigrations] FTS5 unavailable — file search will use LIKE queries (\(error))")
        }
    }

    static func v3(_ db: Database) throws {
        // wired.account.file.search_files was defined in the spec but omitted from the
        // wired.account.privileges collection, so it was never seeded or synced for any
        // account. Backfill it now for every user and group, inheriting the value of
        // wired.account.file.get_info (the neighbouring privilege).

        try db.execute(sql: """
            INSERT OR IGNORE INTO user_privileges (name, value, user_id)
            SELECT 'wired.account.file.search_files', COALESCE(ref.value, 0), u.id
            FROM users u
            LEFT JOIN user_privileges ref
                ON ref.user_id = u.id AND ref.name = 'wired.account.file.get_info'
        """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO group_privileges (name, value, group_id)
            SELECT 'wired.account.file.search_files', COALESCE(ref.value, 0), g.id
            FROM groups g
            LEFT JOIN group_privileges ref
                ON ref.group_id = g.id AND ref.name = 'wired.account.file.get_info'
        """)
    }

    // SECURITY (FINDING_A_004): Add password_salt column for salted SHA-256 hashing
    static func v4(_ db: Database) throws {
        try db.alter(table: "users") { t in
            t.add(column: "password_salt", .text)
        }
    }

    static func v5(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO user_privileges (name, value, user_id)
            SELECT 'wired.account.board.search_boards', COALESCE(ref.value, 0), u.id
            FROM users u
            LEFT JOIN user_privileges ref
                ON ref.user_id = u.id AND ref.name = 'wired.account.board.read_boards'
        """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO group_privileges (name, value, group_id)
            SELECT 'wired.account.board.search_boards', COALESCE(ref.value, 0), g.id
            FROM groups g
            LEFT JOIN group_privileges ref
                ON ref.group_id = g.id AND ref.name = 'wired.account.board.read_boards'
        """)
    }

    static func v6(_ db: Database) throws {
        try db.create(table: "banlist", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("ip_pattern", .text).notNull().unique()
            t.column("expiration_date", .datetime)
        }
    }

    static func v7(_ db: Database) throws {
        try db.create(table: "events", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("event_code", .integer).notNull()
            t.column("parameters_text", .text)
            t.column("time", .datetime).notNull()
            t.column("nick", .text).notNull()
            t.column("login", .text).notNull()
            t.column("ip", .text).notNull()
        }

        try db.create(index: "events_time", on: "events", columns: ["time"], ifNotExists: true)
        try db.create(index: "events_nick", on: "events", columns: ["nick"], ifNotExists: true)
        try db.create(index: "events_login", on: "events", columns: ["login"], ifNotExists: true)
        try db.create(index: "events_ip", on: "events", columns: ["ip"], ifNotExists: true)
    }

    static func v8(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO user_privileges (name, value, user_id)
            SELECT 'wired.account.file.sync.sync_files', COALESCE(ref.value, 0), u.id
            FROM users u
            LEFT JOIN user_privileges ref
                ON ref.user_id = u.id AND ref.name = 'wired.account.file.get_info'
        """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO group_privileges (name, value, group_id)
            SELECT 'wired.account.file.sync.sync_files', COALESCE(ref.value, 0), g.id
            FROM groups g
            LEFT JOIN group_privileges ref
                ON ref.group_id = g.id AND ref.name = 'wired.account.file.get_info'
        """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO user_privileges (name, value, user_id)
            SELECT 'wired.account.file.sync.delete_remote', COALESCE(ref.value, 0), u.id
            FROM users u
            LEFT JOIN user_privileges ref
                ON ref.user_id = u.id AND ref.name = 'wired.account.file.delete_files'
        """)

        try db.execute(sql: """
            INSERT OR IGNORE INTO group_privileges (name, value, group_id)
            SELECT 'wired.account.file.sync.delete_remote', COALESCE(ref.value, 0), g.id
            FROM groups g
            LEFT JOIN group_privileges ref
                ON ref.group_id = g.id AND ref.name = 'wired.account.file.delete_files'
        """)
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

        // ── index (B-tree, real_path lookup) ────────────────────────────────
        try db.create(
            index: "index_real_path",
            on: "index",
            columns: ["real_path"],
            ifNotExists: true
        )

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

        // Security: per-recipient limit (100 messages) to prevent storage DoS
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS offline_messages_per_recipient_limit
            BEFORE INSERT ON offline_messages
            BEGIN
                SELECT RAISE(ABORT, 'per-recipient offline message limit exceeded')
                WHERE (SELECT COUNT(*) FROM offline_messages
                       WHERE recipient_identity = NEW.recipient_identity) >= 100;
            END;
        """)
    }
}
