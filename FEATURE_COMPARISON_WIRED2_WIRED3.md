# Implemented Features Comparison

Comparison between:

- legacy C server: `../../Wired 2020-2021/wired`
- new Swift server: `.`

## Objective

Identify:

- legacy features already ported to the Swift version
- new features added in Wired 3
- features that are likely missing or only partially carried over

## Method

The comparison below is based on:

- legacy business modules in `wired/*.c`
- P7 message routing in `wired/messages.c`
- message routing in `Sources/wired3/Core/ServerController.swift`
- Swift controllers in `Sources/wired3/Controllers`
- legacy configuration `wired/wired.conf.in`
- Swift configuration `Sources/wired3/config.ini`

## Legend

- `Ported`: legacy feature present on the Swift side
- `Extended`: legacy feature present and enhanced in Wired 3
- `Partial`: partial presence, change of scope, or loss of some operations
- `Missing`: no visible equivalent on the Swift side
- `New`: feature introduced in Wired 3, absent from the legacy server

## Summary

Overall functional parity is good for the server core:

- authentication and sessions
- user management
- private messages and broadcast
- boards, threads, posts
- file transfers
- account administration
- banlist
- events
- logs
- trackers

The most notable gaps concern:

- some file metadata operations inherited from Wired 2
- a few legacy server operational functions

Recent parity completions on the Swift side include:

- persistent local tracker registry storage
- native filesystem monitoring for out-of-band changes on macOS and Linux

## Parity Table

| Domain | Feature | Legacy C Server | New Swift Server | Status | Notes |
|---|---|---|---|---|---|
| Connection | Handshake / `wired.client_info` / `wired.send_login` / ping | Yes | Yes | Ported | Routing present in `wired/messages.c` and `Sources/wired3/Core/ServerController.swift`. |
| Connection | Mandatory encryption | Yes | Yes | Ported | Legacy: `force encryption`; new: `advanced.cipher = SECURE_ONLY`. |
| Connection | Persistent server identity / TOFU | No | Yes | New | Implemented via `ServerIdentity` on the Swift side. |
| Connection | Brute-force protection / rate limiting | No | Yes | New | Login failure limits, connection caps, broadcast limits. |
| Users | `wired.user.get_users` | Yes | Yes | Ported | Management present on Swift side in `ServerController+Users.swift`. |
| Users | `wired.user.get_info` | Yes | Yes | Ported | Functional parity visible. |
| Users | `wired.user.set_nick` | Yes | Yes | Ported | Present in Swift router. |
| Users | `wired.user.set_status` | Yes | Yes | Ported | Present in Swift router. |
| Users | `wired.user.set_icon` | Yes | Yes | Ported | Present in Swift router. |
| Users | `wired.user.set_idle` | Yes | Yes | Ported | Present in Swift router. |
| Users | `wired.user.disconnect_user` | Yes | Yes | Ported | Present in Swift router. |
| Users | `wired.user.ban_user` | Yes | Yes | Ported | Present in Swift router. |
| Chat | Ad-hoc private chat `wired.chat.create_chat` | Yes | Yes | Ported | Legacy feature carried over. |
| Chat | Invitation / join / leave / kick | Yes | Yes | Ported | `invite_user`, `decline_invitation`, `join_chat`, `leave_chat`, `kick_user`. |
| Chat | Chat topic `wired.chat.set_topic` | Yes | Yes | Ported | Carried over to Swift. |
| Chat | `wired.chat.send_say` / `wired.chat.send_me` | Yes | Yes | Ported | Carried over to Swift. |
| Chat | Public chat list | No | Yes | New | `wired.chat.get_chats`. |
| Chat | Create/delete public chats | No | Yes | New | `wired.chat.create_public_chat`, `wired.chat.delete_public_chat`. |
| Chat | Typing indicator | No | Yes | New | `wired.chat.send_typing`. |
| Messages | Private message `wired.message.send_message` | Yes | Yes | Extended | Ported and enhanced with attachments. |
| Messages | Broadcast `wired.message.send_broadcast` | Yes | Yes | Ported | Ported, with additional rate limiting on Swift side. |
| Attachments | Upload / preview / binary retrieval | No | Yes | New | `wired.attachment.*` domain absent from C server. |
| Boards | `wired.board.get_boards` | Yes | Yes | Ported | Visible parity. |
| Boards | `wired.board.get_threads` / `wired.board.get_thread` | Yes | Yes | Ported | Visible parity. |
| Boards | CRUD boards | Yes | Yes | Ported | `add_board`, `rename_board`, `move_board`, `delete_board`, `get_board_info`, `set_board_info`. |
| Boards | CRUD threads / posts | Yes | Yes | Ported | `add_thread`, `edit_thread`, `move_thread`, `delete_thread`, `add_post`, `edit_post`, `delete_post`. |
| Boards | Board subscriptions | Yes | Yes | Ported | `subscribe_boards`, `unsubscribe_boards`. |
| Boards | Remote search | No | Yes | New | `wired.board.search`. |
| Boards | Emoji reactions | No | Yes | New | `wired.board.get_reactions`, `wired.board.add_reaction`. |
| Files | `wired.file.list_directory` | Yes | Yes | Ported | Legacy feature carried over. |
| Files | `wired.file.get_info` | Yes | Yes | Ported | Carried over with metadata exposure. |
| Files | `wired.file.preview_file` | Yes | Yes | Ported | Carried over to Swift. |
| Files | `wired.file.create_directory` | Yes | Yes | Ported | Carried over to Swift. |
| Files | `wired.file.delete` | Yes | Yes | Ported | Carried over to Swift. |
| Files | `wired.file.move` | Yes | Yes | Ported | Carried over to Swift. |
| Files | `wired.file.search` | Yes | Yes | Extended | Modern SQLite index with FTS5 if available, `LIKE` fallback. |
| Files | `wired.file.subscribe_directory` / `unsubscribe_directory` | Yes | Yes | Ported | Notifications maintained on Swift side. |
| Files | `wired.file.set_type` | Yes | Yes | Extended | Carried over and extended with `sync` type. |
| Files | `wired.file.set_permissions` | Yes | Yes | Extended | Carried over, with additional sync policy management. |
| Files | `wired.file.link` | Yes | Not visible | Ported | Legacy handler present in `wired/messages.c`, not routed in `ServerController.swift`. |
| Files | `wired.file.set_comment` | Yes | Not visible | Ported | New server returns `wired.file.comment`, but does not route a setter. |
| Files | `wired.file.set_executable` | Yes | Not visible | Ported | New server returns `wired.file.executable`, but does not route a setter. |
| Files | `wired.file.set_label` | Yes | Not visible | Ported | New server returns `wired.file.label`, but does not route a setter. |
| Files | Directory sync | No | Yes | New | `wired.file.set_sync_policy` and sync privileges. |
| Transfers | `wired.transfer.download_file` | Yes | Yes | Ported | Carried over to Swift. |
| Transfers | `wired.transfer.upload_file` | Yes | Yes | Ported | Carried over to Swift. |
| Transfers | `wired.transfer.upload_directory` | Yes | Yes | Ported | Carried over to Swift. |
| Accounts | List users / groups | Yes | Yes | Ported | `wired.account.list_users`, `wired.account.list_groups`. |
| Accounts | Read user / group | Yes | Yes | Ported | `wired.account.read_user`, `wired.account.read_group`. |
| Accounts | Create user / group | Yes | Yes | Ported | `wired.account.create_user`, `wired.account.create_group`. |
| Accounts | Edit user / group | Yes | Yes | Ported | `wired.account.edit_user`, `wired.account.edit_group`. |
| Accounts | Delete user / group | Yes | Yes | Ported | `wired.account.delete_user`, `wired.account.delete_group`. |
| Accounts | Change password | Yes | Yes | Extended | Ported with modernized security model on Swift side. |
| Accounts | Subscribe to account changes | Yes | Yes | Ported | `subscribe_accounts`, `unsubscribe_accounts`. |
| Banlist | Read / add / delete | Yes | Yes | Ported | `wired.banlist.*` domain carried over. |
| Events | `wired.event.get_first_time` | Yes | Yes | Ported | Carried over to Swift. |
| Events | `wired.event.get_events` | Yes | Yes | Ported | Carried over to Swift. |
| Events | `wired.event.subscribe` / `unsubscribe` | Yes | Yes | Ported | Carried over to Swift. |
| Events | `wired.event.delete_events` | Yes | Yes | Ported | Carried over to Swift. |
| Events | Automatic event purge via config | Yes | Not visible | Ported | Legacy: `events time`; new: manual deletion only. |
| Logs | `wired.log.get_log` | Yes | Yes | Ported | Carried over to Swift. |
| Logs | `wired.log.subscribe` / `unsubscribe` | Yes | Yes | Ported | Carried over to Swift. |
| Settings | `wired.settings.get_settings` | Yes | Yes | Ported | Carried over to Swift. |
| Settings | `wired.settings.set_settings` | Yes | Yes | Ported | Carried over to Swift. |
| Settings | Name, description, banner, transfer quotas, trackers | Yes | Yes | Ported | Fields present in Swift setter. |
| Settings | Automatic SQLite database snapshots | Yes | Not visible | Ported | Legacy: `snapshots`, `snapshot time`; no visible equivalent in Swift `config.ini`. |
| Settings | Auto NAT-PMP / UPnP port mapping | Yes | Not visible | Discontinued | Legacy: `map port` + `portmap.c`; no visible equivalent on Swift side. |
| Tracker | `wired.tracker.get_categories` | Yes | Yes | Ported | Carried over to Swift. |
| Tracker | `wired.tracker.get_servers` | Yes | Yes | Ported | Carried over to Swift. |
| Tracker | `wired.tracker.send_register` / `send_update` | Yes | Yes | Ported | Carried over to Swift. |
| Tracker | Outgoing registration to remote trackers | Yes | Yes | Ported | Handled by `OutgoingTrackersController`. |
| Tracker | Local tracker registry persistence | Yes | Yes | Ported | Persisted in SQLite via `TrackerController.swift` + `TrackedServerRecord.swift`, reloaded at startup and purged on expiration. |
| Indexing | Periodic re-indexing | Yes | Yes | Ported | Legacy `index time`, new `reindex_interval`. |
| Indexing | Real-time detection of out-of-band filesystem changes | Yes | Yes | Ported | Native monitoring via `FSEvents` on macOS and `inotify` on Linux, with debounced reindex + directory notifications. |
| Security | Known default admin password | Yes | No | Extended | New server generates a random password at bootstrap. |
| Security | Legacy RSA handshake | Yes | No | Intentional change | Replaced by ECDH / ECDSA in Wired 3. |

## Legacy Features to Prioritize for More Complete Parity

The most concrete remaining legacy parity questions are now concentrated in:

1. a few document-status mismatches in older comparison notes
2. discontinued operational features such as automatic NAT-PMP / UPnP port mapping

## Main References

### Legacy server

- `../../Wired 2020-2021/wired/wired/messages.c`
- `../../Wired 2020-2021/wired/wired/files.c`
- `../../Wired 2020-2021/wired/wired/servers.c`
- `../../Wired 2020-2021/wired/wired/portmap.c`
- `../../Wired 2020-2021/wired/wired/wired.conf.in`

### New server

- `Sources/wired3/Core/ServerController.swift`
- `Sources/wired3/Core/ServerController+Boards.swift`
- `Sources/wired3/Core/ServerController+Admin.swift`
- `Sources/wired3/Controllers/FilesController.swift`
- `Sources/wired3/Controllers/EventsController.swift`
- `Sources/wired3/Controllers/TrackerController.swift`
- `Sources/wired3/Controllers/OutgoingTrackersController.swift`
- `Sources/wired3/Controllers/IndexController.swift`
- `Sources/wired3/config.ini`

## Note

This document is a static comparison based on the code present in both repositories. It is not a complete behavioral runtime audit, but it provides a solid basis for driving the remaining porting work.
