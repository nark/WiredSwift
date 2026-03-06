#if os(Linux)
import CSQLite

// sqlite-nio prefixes SQLite C symbols with `sqlite_nio_` to avoid ABI clashes
// with system SQLite. wired3 uses the canonical sqlite3_* names, so remap them.
let sqlite3_open = sqlite_nio_sqlite3_open
let sqlite3_open_v2 = sqlite_nio_sqlite3_open_v2
let sqlite3_close = sqlite_nio_sqlite3_close
let sqlite3_exec = sqlite_nio_sqlite3_exec
let sqlite3_errmsg = sqlite_nio_sqlite3_errmsg
let sqlite3_prepare_v2 = sqlite_nio_sqlite3_prepare_v2
let sqlite3_finalize = sqlite_nio_sqlite3_finalize
let sqlite3_step = sqlite_nio_sqlite3_step
let sqlite3_bind_text = sqlite_nio_sqlite3_bind_text
let sqlite3_bind_int = sqlite_nio_sqlite3_bind_int
let sqlite3_bind_double = sqlite_nio_sqlite3_bind_double
let sqlite3_bind_null = sqlite_nio_sqlite3_bind_null
let sqlite3_bind_blob = sqlite_nio_sqlite3_bind_blob
let sqlite3_column_text = sqlite_nio_sqlite3_column_text
let sqlite3_column_int = sqlite_nio_sqlite3_column_int
let sqlite3_column_double = sqlite_nio_sqlite3_column_double
let sqlite3_column_type = sqlite_nio_sqlite3_column_type
let sqlite3_column_blob = sqlite_nio_sqlite3_column_blob
let sqlite3_column_bytes = sqlite_nio_sqlite3_column_bytes
#endif
