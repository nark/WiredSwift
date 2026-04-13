import Foundation
#if canImport(CoreServices)
import CoreServices
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class FilesystemMonitor {
    typealias EventHandler = ([String]) -> Void

    private let debounceInterval: TimeInterval
    private let eventHandler: EventHandler
    private let stateQueue = DispatchQueue(label: "wired3.filesystem-monitor.state", qos: .utility)

    private var watchedPath: String
    private var pendingPaths = Set<String>()
    private var pendingWorkItem: DispatchWorkItem?

    #if canImport(CoreServices)
    private let streamQueue = DispatchQueue(label: "wired3.filesystem-monitor.stream", qos: .utility)
    private var stream: FSEventStreamRef?
    #elseif canImport(Glibc)
    private let inotifyQueue = DispatchQueue(label: "wired3.filesystem-monitor.inotify", qos: .utility)
    private var inotifyFileDescriptor: Int32 = -1
    private var inotifyReadSource: DispatchSourceRead?
    private var watchedDirectoriesByDescriptor: [Int32: String] = [:]
    #endif

    init(path: String, debounceInterval: TimeInterval = 0.35, eventHandler: @escaping EventHandler) {
        self.watchedPath = path
        self.debounceInterval = debounceInterval
        self.eventHandler = eventHandler
    }

    @discardableResult
    func start() -> Bool {
        #if canImport(CoreServices)
        stateQueue.sync {
            pendingPaths.removeAll()
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, numEvents, eventPathsPointer, _, _) in
                guard let info else { return }
                let monitor = Unmanaged<FilesystemMonitor>.fromOpaque(info).takeUnretainedValue()
                let eventPaths = unsafeBitCast(eventPathsPointer, to: NSArray.self) as? [String] ?? []
                monitor.processObservedPaths(Array(eventPaths.prefix(Int(numEvents))))
            },
            &context,
            [watchedPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(stream, streamQueue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }

        self.stream = stream
        return true
        #elseif canImport(Glibc)
        stateQueue.sync {
            pendingPaths.removeAll()
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
        }

        let descriptor = inotify_init1(Int32(IN_NONBLOCK))
        guard descriptor >= 0 else {
            return false
        }

        inotifyFileDescriptor = descriptor

        guard installRecursiveWatches(rootPath: watchedPath) else {
            stop()
            return false
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: inotifyQueue)
        readSource.setEventHandler { [weak self] in
            self?.drainInotifyEvents()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.inotifyFileDescriptor >= 0 {
                _ = Glibc.close(self.inotifyFileDescriptor)
                self.inotifyFileDescriptor = -1
            }
        }
        inotifyReadSource = readSource
        readSource.resume()
        return true
        #else
        return false
        #endif
    }

    func stop() {
        stateQueue.sync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
            pendingPaths.removeAll()
        }

        #if canImport(CoreServices)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        #elseif canImport(Glibc)
        watchedDirectoriesByDescriptor.removeAll()
        inotifyReadSource?.cancel()
        inotifyReadSource = nil
        if inotifyFileDescriptor >= 0 {
            _ = Glibc.close(inotifyFileDescriptor)
            inotifyFileDescriptor = -1
        }
        #endif
    }

    func processObservedPaths(_ paths: [String]) {
        let normalizedPaths = paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { !$0.isEmpty }
        guard !normalizedPaths.isEmpty else { return }

        stateQueue.async {
            self.pendingPaths.formUnion(normalizedPaths)
            self.pendingWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingPathsFromStateQueue()
            }
            self.pendingWorkItem = workItem
            self.stateQueue.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }

    private func flushPendingPathsFromStateQueue() {
        let paths = pendingPaths.sorted()
        pendingPaths.removeAll()
        pendingWorkItem = nil
        guard !paths.isEmpty else { return }
        eventHandler(paths)
    }

    #if canImport(Glibc)
    private func installRecursiveWatches(rootPath: String) -> Bool {
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        guard addWatch(forDirectory: normalizedRoot) else {
            return false
        }

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: normalizedRoot, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return true
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            guard addWatch(forDirectory: url.standardizedFileURL.path) else {
                return false
            }
        }

        return true
    }

    private func addWatch(forDirectory path: String) -> Bool {
        guard inotifyFileDescriptor >= 0 else { return false }
        guard FileManager.default.fileExists(atPath: path) else { return false }
        if watchedDirectoriesByDescriptor.values.contains(path) {
            return true
        }

        let mask = UInt32(
            IN_CREATE |
            IN_DELETE |
            IN_DELETE_SELF |
            IN_MODIFY |
            IN_MOVED_FROM |
            IN_MOVED_TO |
            IN_MOVE_SELF |
            IN_ATTRIB |
            IN_CLOSE_WRITE
        )

        let descriptor = path.withCString { inotify_add_watch(inotifyFileDescriptor, $0, mask) }
        guard descriptor >= 0 else {
            return false
        }

        watchedDirectoriesByDescriptor[descriptor] = path
        return true
    }

    private func drainInotifyEvents() {
        guard inotifyFileDescriptor >= 0 else { return }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = Glibc.read(inotifyFileDescriptor, buffer, bufferSize)
            if bytesRead < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                return
            }

            if bytesRead == 0 {
                return
            }

            var offset = 0
            while offset + MemoryLayout<inotify_event>.size <= bytesRead {
                let eventPointer = UnsafeRawPointer(buffer.advanced(by: offset)).assumingMemoryBound(to: inotify_event.self)
                let event = eventPointer.pointee
                let nameOffset = offset + MemoryLayout<inotify_event>.size
                let nameLength = Int(event.len)

                let watchedDirectory = watchedDirectoriesByDescriptor[event.wd]
                let eventPath = resolvedInotifyEventPath(
                    watchedDirectory: watchedDirectory,
                    nameBaseAddress: buffer.advanced(by: nameOffset),
                    nameLength: nameLength
                )

                if let eventPath {
                    processObservedPaths([eventPath])
                    if event.mask & UInt32(IN_ISDIR) != 0,
                       event.mask & UInt32(IN_CREATE) != 0 || event.mask & UInt32(IN_MOVED_TO) != 0 {
                        _ = installRecursiveWatches(rootPath: eventPath)
                    }
                }

                if event.mask & UInt32(IN_IGNORED) != 0 || event.mask & UInt32(IN_DELETE_SELF) != 0 || event.mask & UInt32(IN_MOVE_SELF) != 0 {
                    watchedDirectoriesByDescriptor.removeValue(forKey: event.wd)
                }

                offset += MemoryLayout<inotify_event>.size + nameLength
            }
        }
    }

    private func resolvedInotifyEventPath(
        watchedDirectory: String?,
        nameBaseAddress: UnsafeMutablePointer<UInt8>,
        nameLength: Int
    ) -> String? {
        guard let watchedDirectory else { return nil }
        guard nameLength > 0 else { return watchedDirectory }

        let name = nameBaseAddress.withMemoryRebound(to: CChar.self, capacity: nameLength) {
            String(cString: $0)
        }
        guard !name.isEmpty else { return watchedDirectory }

        return URL(fileURLWithPath: watchedDirectory)
            .appendingPathComponent(name)
            .standardizedFileURL
            .path
    }
    #endif
}
