#!/usr/bin/env python3
"""
migrate-from-wired25.py
Migrates users, groups and bans from a Wired 2.5 SQLite database
into an existing Wired 3 (wired3) SQLite database.

Usage:
    python3 Scripts/migrate-from-wired25.py \
        --source  /path/to/wired25/database.sqlite3 \
        --target  /path/to/wired3/database.sqlite3  \
        [--dry-run]   # analyse only, no writes
        [--overwrite] # replace existing users/groups in Wired 3

IMPORTANT:
  • Make a backup of both databases before running!
  • Wired 2.5 stores passwords as SHA1 hashes, Wired 3 uses SHA256 + salt.
    Passwords are copied as-is. Wired 3 will treat them as "legacy" and users
    will need to set a new password on first login (or you reset them manually).
  • The 'admin' account that Wired 3 creates by default is never overwritten
    unless --overwrite is passed.
"""

import sqlite3
import argparse
import sys
from datetime import datetime, timezone

# ── Privilege mapping: Wired 2.5 column → Wired 3 privilege name ─────────────
#
# Boolean privileges (0/1 in 2.5, stored as separate rows in 3)
BOOL_PRIVILEGE_MAP = {
    "user_get_info":                        "wired.account.user.get_info",
    "user_disconnect_users":                "wired.account.user.disconnect_users",
    "user_ban_users":                       "wired.account.user.ban_users",
    "user_cannot_be_disconnected":          "wired.account.user.cannot_be_disconnected",
    "user_cannot_set_nick":                 "wired.account.user.cannot_set_nick",
    "user_get_users":                       "wired.account.user.get_users",
    "chat_kick_users":                      "wired.account.chat.kick_users",
    "chat_set_topic":                       "wired.account.chat.set_topic",
    "chat_create_chats":                    "wired.account.chat.create_chats",
    "message_send_messages":                "wired.account.message.send_messages",
    "message_broadcast":                    "wired.account.message.broadcast",
    "file_list_files":                      "wired.account.file.list_files",
    "file_search_files":                    "wired.account.file.search_files",
    "file_get_info":                        "wired.account.file.get_info",
    "file_create_links":                    "wired.account.file.create_links",
    "file_rename_files":                    "wired.account.file.rename_files",
    "file_set_type":                        "wired.account.file.set_type",
    "file_set_comment":                     "wired.account.file.set_comment",
    "file_set_permissions":                 "wired.account.file.set_permissions",
    "file_set_executable":                  "wired.account.file.set_executable",
    "file_set_label":                       "wired.account.file.set_label",
    "file_create_directories":              "wired.account.file.create_directories",
    "file_move_files":                      "wired.account.file.move_files",
    "file_delete_files":                    "wired.account.file.delete_files",
    "file_access_all_dropboxes":            "wired.account.file.access_all_dropboxes",
    "account_change_password":              "wired.account.account.change_password",
    "account_list_accounts":               "wired.account.account.list_accounts",
    "account_read_accounts":               "wired.account.account.read_accounts",
    "account_create_users":                "wired.account.account.create_users",
    "account_edit_users":                  "wired.account.account.edit_users",
    "account_delete_users":                "wired.account.account.delete_users",
    "account_create_groups":               "wired.account.account.create_groups",
    "account_edit_groups":                 "wired.account.account.edit_groups",
    "account_delete_groups":               "wired.account.account.delete_groups",
    "account_raise_account_privileges":    "wired.account.account.raise_account_privileges",
    "transfer_download_files":             "wired.account.transfer.download_files",
    "transfer_upload_files":               "wired.account.transfer.upload_files",
    "transfer_upload_anywhere":            "wired.account.transfer.upload_anywhere",
    "transfer_upload_directories":         "wired.account.transfer.upload_directories",
    "board_read_boards":                   "wired.account.board.read_boards",
    "board_add_boards":                    "wired.account.board.add_boards",
    "board_move_boards":                   "wired.account.board.move_boards",
    "board_rename_boards":                 "wired.account.board.rename_boards",
    "board_delete_boards":                 "wired.account.board.delete_boards",
    "board_get_board_info":                "wired.account.board.get_board_info",
    "board_set_board_info":                "wired.account.board.set_board_info",
    "board_add_threads":                   "wired.account.board.add_threads",
    "board_move_threads":                  "wired.account.board.move_threads",
    "board_add_posts":                     "wired.account.board.add_posts",
    "board_edit_own_threads_and_posts":    "wired.account.board.edit_own_threads_and_posts",
    "board_edit_all_threads_and_posts":    "wired.account.board.edit_all_threads_and_posts",
    "board_delete_own_threads_and_posts":  "wired.account.board.delete_own_threads_and_posts",
    "board_delete_all_threads_and_posts":  "wired.account.board.delete_all_threads_and_posts",
    "log_view_log":                        "wired.account.log.view_log",
    "events_view_events":                  "wired.account.events.view_events",
    "settings_get_settings":              "wired.account.settings.get_settings",
    "settings_set_settings":              "wired.account.settings.set_settings",
    "banlist_get_bans":                    "wired.account.banlist.get_bans",
    "banlist_add_bans":                    "wired.account.banlist.add_bans",
    "banlist_delete_bans":                 "wired.account.banlist.delete_bans",
    "tracker_list_servers":                "wired.account.tracker.list_servers",
    "tracker_register_servers":            "wired.account.tracker.register_servers",
}

# Integer privileges (stored as value in Wired 3, still as separate privilege rows)
INT_PRIVILEGE_MAP = {
    "file_recursive_list_depth_limit":     "wired.account.file.recursive_list_depth_limit",
    "transfer_download_speed_limit":       "wired.account.transfer.download_speed_limit",
    "transfer_upload_speed_limit":         "wired.account.transfer.upload_speed_limit",
    "transfer_download_limit":             "wired.account.transfer.download_limit",
    "transfer_upload_limit":               "wired.account.transfer.upload_limit",
}


def log(msg):
    print(msg)


def warn(msg):
    print(f"  WARNING: {msg}")


def migrate_groups(src, dst, dry_run, overwrite):
    log("\n── Groups ───────────────────────────────────────────────")
    rows = src.execute("SELECT name, color FROM groups").fetchall()
    log(f"  Found {len(rows)} group(s) in Wired 2.5")

    migrated = skipped = 0
    for row in rows:
        name  = row["name"]
        color = row["color"]  # already in "wired.account.color.xxx" format or NULL

        if dry_run:
            log(f"  DRY   group '{name}'  color={color}")
            migrated += 1
            continue

        exists = dst.execute(
            "SELECT id FROM groups WHERE name = ?", (name,)
        ).fetchone()

        if exists and not overwrite:
            log(f"  SKIP  group '{name}' (already exists)")
            skipped += 1
            continue

        if exists:
            dst.execute(
                "UPDATE groups SET color = ? WHERE name = ?",
                (color, name)
            )
            group_id = exists["id"]
            log(f"  UPD   group '{name}'")
        else:
            cur = dst.execute(
                "INSERT INTO groups (name, color) VALUES (?, ?)",
                (name, color)
            )
            group_id = cur.lastrowid
            log(f"  ADD   group '{name}'")

        # Migrate group privileges
        _migrate_privileges(
            src_row=src.execute("SELECT * FROM groups WHERE name = ?", (name,)).fetchone(),
            dst=dst,
            table="group_privileges",
            fk_col="group_id",
            fk_val=group_id,
            dry_run=dry_run,
        )
        migrated += 1

    log(f"  → {migrated} migrated, {skipped} skipped")


def migrate_users(src, dst, dry_run, overwrite):
    log("\n── Users ────────────────────────────────────────────────")
    rows = src.execute("SELECT * FROM users").fetchall()
    log(f"  Found {len(rows)} user(s) in Wired 2.5")

    migrated = skipped = 0
    now = datetime.now(timezone.utc).isoformat()

    for row in rows:
        username = row["name"]

        # Map fields
        password          = row["password"] or ""
        full_name         = row["full_name"]
        comment           = row["comment"]
        creation_time     = row["creation_time"]
        modification_time = row["modification_time"]
        login_time        = row["login_time"]
        edited_by         = row["edited_by"]
        downloads         = row["downloads"] or 0
        download_xfr      = row["download_transferred"] or 0
        uploads           = row["uploads"] or 0
        upload_xfr        = row["upload_transferred"] or 0
        group             = row["group"]
        groups            = row["groups"]
        color             = row["color"]
        files             = row["files"]

        if dry_run:
            log(f"  DRY   user '{username}'  group={group}  color={color}")
            migrated += 1
            continue

        exists = dst.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()

        if exists and not overwrite:
            log(f"  SKIP  user '{username}' (already exists)")
            skipped += 1
            continue

        if exists:
            dst.execute("""
                UPDATE users SET
                    password=?, full_name=?, comment=?,
                    creation_time=?, modification_time=?, login_time=?,
                    edited_by=?, downloads=?, download_transferred=?,
                    uploads=?, upload_transferred=?,
                    "group"=?, groups=?, color=?, files=?,
                    password_salt=NULL
                WHERE username=?
            """, (
                password, full_name, comment,
                creation_time, modification_time, login_time,
                edited_by, downloads, download_xfr,
                uploads, upload_xfr,
                group, groups, color, files,
                username,
            ))
            user_id = exists["id"]
            # Remove old privileges so they get re-written cleanly
            dst.execute("DELETE FROM user_privileges WHERE user_id = ?", (user_id,))
            log(f"  UPD   user '{username}'")
        else:
            cur = dst.execute("""
                INSERT INTO users (
                    username, password, password_salt,
                    full_name, comment,
                    creation_time, modification_time, login_time,
                    edited_by, downloads, download_transferred,
                    uploads, upload_transferred,
                    "group", groups, color, files
                ) VALUES (?,?,NULL,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                username, password,
                full_name, comment,
                creation_time, modification_time, login_time,
                edited_by, downloads, download_xfr,
                uploads, upload_xfr,
                group, groups, color, files,
            ))
            user_id = cur.lastrowid
            log(f"  ADD   user '{username}'")

        # Migrate user privileges
        _migrate_privileges(
            src_row=row,
            dst=dst,
            table="user_privileges",
            fk_col="user_id",
            fk_val=user_id,
            dry_run=dry_run,
        )
        migrated += 1

    log(f"  → {migrated} migrated, {skipped} skipped")


def migrate_bans(src, dst, dry_run, overwrite):
    log("\n── Bans ─────────────────────────────────────────────────")
    rows = src.execute("SELECT ip, expiration_date FROM banlist").fetchall()
    log(f"  Found {len(rows)} ban(s) in Wired 2.5")

    migrated = skipped = 0
    for row in rows:
        ip_pattern      = row["ip"]
        expiration_date = row["expiration_date"]

        if dry_run:
            log(f"  DRY   ban '{ip_pattern}'  expires={expiration_date}")
            migrated += 1
            continue

        exists = dst.execute(
            "SELECT id FROM banlist WHERE ip_pattern = ?", (ip_pattern,)
        ).fetchone()

        if exists and not overwrite:
            log(f"  SKIP  ban '{ip_pattern}'")
            skipped += 1
            continue

        if exists:
            dst.execute(
                "UPDATE banlist SET expiration_date = ? WHERE ip_pattern = ?",
                (expiration_date, ip_pattern)
            )
        else:
            dst.execute(
                "INSERT INTO banlist (ip_pattern, expiration_date) VALUES (?, ?)",
                (ip_pattern, expiration_date)
            )
        log(f"  ADD   ban '{ip_pattern}'  expires={expiration_date or 'never'}")
        migrated += 1

    log(f"  → {migrated} migrated, {skipped} skipped")


def _migrate_privileges(src_row, dst, table, fk_col, fk_val, dry_run):
    """Write privilege rows for a single user or group."""
    cols = src_row.keys()

    for src_col, priv_name in BOOL_PRIVILEGE_MAP.items():
        if src_col not in cols:
            continue
        raw = src_row[src_col]
        if raw is None:
            continue
        value = bool(int(raw))
        if not dry_run:
            dst.execute(
                f"INSERT OR REPLACE INTO {table} (name, value, {fk_col}) VALUES (?,?,?)",
                (priv_name, value, fk_val)
            )

    for src_col, priv_name in INT_PRIVILEGE_MAP.items():
        if src_col not in cols:
            continue
        raw = src_row[src_col]
        if raw is None:
            continue
        # Integer privileges: store the integer value cast to BOOLEAN column
        # (Wired 3 treats these as numeric limits — 0 = unlimited)
        value = int(raw)
        if not dry_run:
            dst.execute(
                f"INSERT OR REPLACE INTO {table} (name, value, {fk_col}) VALUES (?,?,?)",
                (priv_name, value, fk_val)
            )


def print_summary(src):
    log("\n── Source database summary ───────────────────────────────")
    for table in ("users", "groups", "banlist"):
        try:
            n = src.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            log(f"  {table:<12} {n} row(s)")
        except Exception:
            log(f"  {table:<12} (not found)")


def main():
    parser = argparse.ArgumentParser(
        description="Migrate Wired 2.5 database to Wired 3 format"
    )
    parser.add_argument("--source",    required=True, help="Path to Wired 2.5 database.sqlite3")
    parser.add_argument("--target",    required=True, help="Path to Wired 3 database.sqlite3")
    parser.add_argument("--dry-run",   action="store_true", help="Analyse only, no writes")
    parser.add_argument("--overwrite", action="store_true", help="Replace existing records in Wired 3")
    args = parser.parse_args()

    log("╔══════════════════════════════════════════════════════════╗")
    log("║        Wired 2.5 → Wired 3  database migration          ║")
    log("╚══════════════════════════════════════════════════════════╝")
    if args.dry_run:
        log("  MODE: DRY RUN – no changes will be written\n")

    src = sqlite3.connect(args.source)
    src.row_factory = sqlite3.Row
    dst = sqlite3.connect(args.target)
    dst.row_factory = sqlite3.Row
    dst.execute("PRAGMA foreign_keys = ON")
    dst.execute("PRAGMA journal_mode = WAL")

    print_summary(src)

    try:
        if not args.dry_run:
            dst.execute("BEGIN")

        migrate_groups(src, dst, args.dry_run, args.overwrite)
        migrate_users(src, dst, args.dry_run, args.overwrite)
        migrate_bans(src, dst, args.dry_run, args.overwrite)

        if not args.dry_run:
            dst.commit()
            log("\n✓ Migration committed successfully.")
        else:
            log("\n✓ Dry run complete – no changes were written.")

        log("")
        log("  NOTE: Passwords were migrated as-is (SHA1 hashes from Wired 2.5).")
        log("        Users will need to set a new password on their first login")
        log("        to Wired 3 (use the admin panel to reset passwords).")

    except Exception as e:
        if not args.dry_run:
            dst.rollback()
        log(f"\n✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        src.close()
        dst.close()


if __name__ == "__main__":
    main()
