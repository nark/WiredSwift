//
//  IndexController.swift
//  wired3
//

import Foundation
import GRDB
import WiredSwift

/// Maintains the SQLite-backed file search index and handles `wired.file.search_files` requests.
///
/// Runs full filesystem traversals on a serial `indexQueue` and supports periodic reindexing,
/// cooperative cancellation, and FTS5-accelerated search with a LIKE-based fallback.
public class IndexController: TableController {

    let filesController: FilesController

    // ── Public stats (read from any thread; written only from indexQueue) ──
    public private(set) var totalFilesSize: UInt64        = 0
    public private(set) var totalFilesCount: UInt64       = 0
    public private(set) var totalDirectoriesCount: UInt64 = 0

    // ── FTS5 availability (set once in init, read-only afterwards) ──────────
    public private(set) var hasFTS5: Bool = false

    // ── Private state (accessed only from indexQueue) ───────────────────────
    // Serial queue: serialises rebuilds and unit updates (addIndex/removeIndex).
    private let indexQueue = DispatchQueue(label: "wired3.index", qos: .utility)
    private var currentGeneration: Int64 = 0
    private var isIndexing: Bool = false
    // When a rebuild is running and another request arrives, set this flag so
    // exactly one extra rebuild is scheduled after the current one finishes.
    private var pendingRebuild: Bool = false

    // ── Cancellation flag — may be written from any thread (signal handler),
    //    read from indexQueue inside the traversal loop.
    //    Protected by cancelLock so there is no data race.
    private let cancelLock = NSLock()
    private var _cancelCurrentRebuild = false
    private var cancelCurrentRebuild: Bool {
        get { cancelLock.withLock { _cancelCurrentRebuild } }
        set { cancelLock.withLock { _cancelCurrentRebuild = newValue } }
    }

    // ── Periodic reindex timer (accessed only from indexQueue) ───────────────
    // Fires every `reindexInterval` seconds. 0 = disabled.
    private var reindexTimer: DispatchSourceTimer?
    private var reindexInterval: TimeInterval = 0

    // ── Init ─────────────────────────────────────────────────────────────────

    /// Creates a new `IndexController` and probes for FTS5 availability.
    ///
    /// - Parameters:
    ///   - databaseController: The shared database controller.
    ///   - filesController: The files controller providing the root path and virtual-path mapping.
    public init(databaseController: DatabaseController, filesController: FilesController) {
        self.filesController = filesController
        super.init(databaseController: databaseController)
        self.hasFTS5 = detectFTS5()
        if hasFTS5 {
            Logger.info("IndexController: FTS5 search index available")
        } else {
            Logger.warning("IndexController: FTS5 not available — using LIKE-based search")
        }
    }

    // MARK: - Public API

    /// Configure the automatic periodic reindex interval.
    /// Pass 0 to disable. Thread-safe; safe to call from any thread including reloadConfig().
    /// The new interval takes effect immediately (the existing timer is cancelled and a new
    /// one is armed with a fresh `interval`-second countdown).
    public func configure(reindexInterval interval: TimeInterval) {
        indexQueue.async { [weak self] in
            self?.schedulePeriodicReindex(interval: interval)
        }
    }

    /// Schedule a full filesystem rebuild. Thread-safe; deduplicates concurrent calls.
    public func indexFiles() {
        indexQueue.async { [weak self] in
            guard let self else { return }
            if self.isIndexing {
                // A rebuild is running — note that one more is needed after it.
                self.pendingRebuild = true
                return
            }
            self.performFullRebuild()
        }
    }

    /// Cancel any in-progress rebuild and start a fresh one immediately.
    /// Thread-safe; safe to call from a signal handler via DispatchSource.
    ///
    /// Cancellation is cooperative: the running traversal loop checks
    /// `cancelCurrentRebuild` between directory entries and exits early.
    /// A new rebuild is queued on `indexQueue` and starts as soon as the
    /// cancelled one has cleaned up.
    public func forceReindex() {
        // Signal the traversal loop to stop. This write is visible to the
        // loop because both sides go through cancelLock.
        cancelCurrentRebuild = true

        // Queue the fresh rebuild on indexQueue. It will execute after the
        // cancelled rebuild's defer block runs (isIndexing reset etc.).
        indexQueue.async { [weak self] in
            guard let self else { return }
            // Reset the cancellation flag so the new rebuild runs normally.
            self.cancelCurrentRebuild = false
            // Discard any stacked pending rebuild — we're doing it right now.
            self.pendingRebuild = false
            self.performFullRebuild()
        }
    }

    /// Index a single newly-created file or directory. Thread-safe.
    public func addIndex(forPath realPath: String) {
        indexQueue.async { [weak self] in
            guard let self else { return }
            self.indexPath(realPath: realPath, generation: self.currentGeneration)
        }
    }

    /// Remove a single entry from the index. Thread-safe.
    public func removeIndex(forPath realPath: String) {
        indexQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.databaseController.dbQueue.write { db in
                    try WiredIndex
                        .filter(Column("real_path") == realPath)
                        .deleteAll(db)
                }
            } catch {
                Logger.error("Cannot remove index for \(realPath): \(error)")
            }
        }
    }

    /// Search the file index for `query` and stream `wired.file.search_list`
    /// replies to `client`, terminating with `wired.file.search_list.done`.
    public func search(query: String, client: Client, message: P7Message) {
        guard let user = client.user else { return }

        guard user.hasPrivilege(name: "wired.account.file.search_files") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            sendSearchDone(client: client, message: message)
            App.serverController.recordEvent(.fileSearched, client: client, parameters: [trimmed])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let results = try self.fetchResults(for: trimmed)
                for entry in results {
                    // F_015: skip files inside dropboxes the user cannot read
                    if let priv = App.filesController.dropBoxPrivileges(forVirtualPath: entry.virtual_path),
                       !App.filesController.managedAccess(forVirtualPath: entry.virtual_path, user: user, privilege: priv).readable {
                        continue
                    }
                    self.sendSearchListEntry(entry: entry, user: user, client: client, message: message)
                }
                self.sendSearchDone(client: client, message: message)
                App.serverController.recordEvent(.fileSearched, client: client, parameters: [trimmed])
            } catch {
                Logger.error("Search failed for query '\(trimmed)': \(error)")
                self.sendSearchDone(client: client, message: message)
            }
        }
    }

    // MARK: - Private — periodic timer

    /// Arm (or re-arm) the periodic reindex timer. Always called from `indexQueue`.
    private func schedulePeriodicReindex(interval: TimeInterval) {
        // Cancel any existing timer first.
        reindexTimer?.cancel()
        reindexTimer = nil
        reindexInterval = interval

        guard interval > 0 else {
            Logger.info("IndexController: periodic reindex disabled")
            return
        }

        // Fire on a global utility queue so the timer itself is not blocked by indexQueue
        // work; it simply enqueues an indexFiles() call which does its own async dispatch.
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .global(qos: .utility))
        // First fire after `interval`, then every `interval`, with up to 60s leeway to
        // allow the OS to coalesce wakeups and save power.
        timer.schedule(deadline: .now() + interval,
                       repeating: interval,
                       leeway: .seconds(60))
        timer.setEventHandler { [weak self] in
            Logger.info("IndexController: periodic reindex triggered (interval \(Int(interval))s)")
            self?.indexFiles()
        }
        timer.resume()
        reindexTimer = timer
        Logger.info("IndexController: periodic reindex armed — every \(Int(interval))s")
    }

    // MARK: - Private — rebuild

    /// Full filesystem traversal. Runs entirely on `indexQueue`.
    private func performFullRebuild() {
        isIndexing = true
        let startTime = Date()
        Logger.info("IndexController: starting full rebuild of \(filesController.rootPath)")

        defer {
            let wasCancelled = cancelCurrentRebuild
            isIndexing = false
            // Only chain a pending rebuild if *we* completed normally (not cancelled).
            // If cancelled, forceReindex() has already queued a fresh rebuild via
            // indexQueue.async; letting pendingRebuild fire here too would cause a
            // redundant extra traversal immediately after the forced one.
            if !wasCancelled && pendingRebuild {
                pendingRebuild = false
                performFullRebuild()
            }
        }

        let newGen = currentGeneration &+ 1
        var newSize: UInt64 = 0
        var newFiles: UInt64 = 0
        var newDirs: UInt64 = 0

        // Track visited canonical paths to break symlink cycles.
        var visited = Set<String>()

        let rootURL = URL(fileURLWithPath: filesController.rootPath)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .canonicalPathKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            Logger.error("IndexController: cannot enumerate \(filesController.rootPath)")
            return
        }

        for case let fileURL as URL in enumerator {
            // Cooperative cancellation check — exits at the next directory entry.
            if cancelCurrentRebuild {
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
                Logger.info("IndexController: rebuild cancelled after \(elapsed)s (gen \(newGen), \(newFiles) files / \(newDirs) dirs indexed so far) — forceReindex pending")
                return
            }

            let realPath = fileURL.path

            // Skip .wired metadata directories
            if realPath.contains("/.wired") { continue }

            // Resolve canonical path to detect symlink cycles
            let canonicalPath = (try? fileURL.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? realPath
            guard visited.insert(canonicalPath).inserted else { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let isDir   = resourceValues?.isDirectory  ?? false
            let isAlias = resourceValues?.isSymbolicLink ?? false
            let size    = UInt64(resourceValues?.fileSize ?? 0)

            let filename    = fileURL.lastPathComponent
            let virtualPath = filesController.virtual(path: realPath)

            indexPath(realPath: realPath,
                      filename: filename,
                      virtualPath: virtualPath,
                      isAlias: isAlias,
                      generation: newGen)

            if isDir {
                newDirs += 1
            } else {
                newFiles += 1
                // "totalFilesSize" intentionally excludes directory entry sizes.
                newSize += size
            }
        }

        // Atomically remove old-generation entries now that new ones are all inserted.
        // FTS5 triggers handle the FTS index automatically.
        do {
            try databaseController.dbQueue.write { db in
                try WiredIndex
                    .filter(Column("generation_id") != newGen)
                    .deleteAll(db)

                // Compact the FTS5 index after a full rebuild for optimal query speed.
                if hasFTS5 {
                    try db.execute(sql: "INSERT INTO file_search(file_search) VALUES('optimize')")
                }
            }
            currentGeneration = newGen
            totalFilesSize        = newSize
            totalFilesCount       = newFiles
            totalDirectoriesCount = newDirs

            let elapsed  = String(format: "%.2f", Date().timeIntervalSince(startTime))
            let sizeDesc = ByteCountFormatter.string(fromByteCount: Int64(newSize), countStyle: .file)
            Logger.info("IndexController: rebuild complete in \(elapsed)s — \(newFiles) files (\(sizeDesc)), \(newDirs) dirs (gen \(newGen))")
        } catch {
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
            Logger.error("IndexController: rebuild finalisation failed after \(elapsed)s: \(error)")
        }
    }

    /// Insert a single entry into the index. Called from `indexQueue`.
    private func indexPath(realPath: String,
                           filename: String? = nil,
                           virtualPath: String? = nil,
                           isAlias: Bool = false,
                           generation: Int64) {
        let name    = filename    ?? realPath.lastPathComponent
        let vpath   = virtualPath ?? filesController.virtual(path: realPath)
        var entry   = WiredIndex(name: name, virtual_path: vpath, real_path: realPath,
                                 alias: isAlias, generation_id: generation)
        do {
            try databaseController.dbQueue.write { db in try entry.insert(db) }
        } catch {
            Logger.error("IndexController: cannot insert index entry for \(realPath): \(error)")
        }
    }

    // MARK: - Private — search

    /// Run a database query and return matching WiredIndex rows.
    private func fetchResults(for query: String) throws -> [WiredIndex] {
        if hasFTS5 {
            return try fts5Search(query: query)
        } else {
            return try likeSearch(query: query)
        }
    }

    private func fts5Search(query: String) throws -> [WiredIndex] {
        // Build a safe FTS5 MATCH expression:
        //   each token is double-quoted (escaping inner quotes)
        //   and suffixed with * for prefix matching.
        //   Multiple tokens are implicit AND.
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let ftsQuery = (tokens.isEmpty ? [query.trimmingCharacters(in: .whitespacesAndNewlines)] : tokens)
            .map { token -> String in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " ")

        return try databaseController.dbQueue.read { db in
            try WiredIndex.fetchAll(db, sql: """
                SELECT i.*
                FROM "index" i
                INNER JOIN file_search ON file_search.rowid = i.id
                WHERE file_search MATCH ?
                ORDER BY bm25(file_search)
                LIMIT 1000
            """, arguments: [ftsQuery])
        }
    }

    private func likeSearch(query: String) throws -> [WiredIndex] {
        // Escape LIKE special characters so user input is treated as a literal string.
        var escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "%", with: "\\%")
        escaped = escaped.replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"

        return try databaseController.dbQueue.read { db in
            try WiredIndex.filter(
                Column("name").like(pattern, escape: "\\") ||
                Column("virtual_path").like(pattern, escape: "\\")
            )
            .limit(1000)
            .fetchAll(db)
        }
    }

    // MARK: - Private — response building

    private func sendSearchListEntry(entry: WiredIndex,
                                     user: User,
                                     client: Client,
                                     message: P7Message) {
        let realPath = entry.real_path

        // Verify the file still exists on disk before reporting it.
        guard FileManager.default.fileExists(atPath: realPath) else { return }

        guard let type = WiredSwift.File.FileType.type(path: realPath) else { return }

        let reply = P7Message(withName: "wired.file.search_list", spec: message.spec)
        reply.addParameter(field: "wired.file.path", value: entry.virtual_path)
        reply.addParameter(field: "wired.file.type", value: type.rawValue)

        let attrs = try? FileManager.default.attributesOfItem(atPath: realPath)
        reply.addParameter(field: "wired.file.creation_time",
                           value: (attrs?[.creationDate] as? Date) ?? Date(timeIntervalSince1970: 0))
        reply.addParameter(field: "wired.file.modification_time",
                           value: (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0))

        reply.addParameter(field: "wired.file.link", value: entry.alias)
        reply.addParameter(field: "wired.file.executable", value: false)
        reply.addParameter(field: "wired.file.label", value: WiredSwift.File.FileLabel.LABEL_NONE.rawValue)
        reply.addParameter(field: "wired.file.volume", value: UInt32(0))

        switch type {
        case .file:
            reply.addParameter(field: "wired.file.data_size", value: WiredSwift.File.size(path: realPath))
            reply.addParameter(field: "wired.file.rsrc_size", value: UInt64(0))
        case .directory, .uploads:
            reply.addParameter(field: "wired.file.directory_count", value: WiredSwift.File.count(path: realPath))
        case .dropbox, .sync:
            reply.addParameter(field: "wired.file.directory_count",
                               value: WiredSwift.File.count(path: realPath))
            if let priv = App.filesController.dropBoxPrivileges(forVirtualPath: entry.virtual_path) {
                let access = App.filesController.managedAccess(forVirtualPath: entry.virtual_path, user: user, privilege: priv)
                reply.addParameter(field: "wired.file.readable", value: access.readable)
                reply.addParameter(field: "wired.file.writable", value: access.writable)
            }
        }

        App.serverController.reply(client: client, reply: reply, message: message)
    }

    private func sendSearchDone(client: Client, message: P7Message) {
        let done = P7Message(withName: "wired.file.search_list.done", spec: message.spec)
        App.serverController.reply(client: client, reply: done, message: message)
    }

    // MARK: - Private — FTS5 detection

    private func detectFTS5() -> Bool {
        do {
            return try databaseController.dbQueue.read { db in
                try db.tableExists("file_search")
            }
        } catch {
            return false
        }
    }
}
