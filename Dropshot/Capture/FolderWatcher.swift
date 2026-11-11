import CoreServices
import Foundation

/// Watches one folder with FSEvents (file-level events, root tracking).
///
/// Thread-safety: all mutable state is confined to `queue`, which is also the queue the
/// stream delivers on.
final class FolderWatcher: @unchecked Sendable {
    enum Change: Sendable {
        /// Paths that were created / renamed / modified.
        case files([String])
        /// The watched folder itself was deleted, renamed or moved.
        case rootChanged
        /// FSEvents dropped events; the folder should be rescanned.
        case needsRescan
    }

    private let folder: URL
    private let handler: @Sendable (Change) -> Void
    private let queue = DispatchQueue(label: "app.dropshot.folder-watcher", qos: .userInitiated)
    private var stream: FSEventStreamRef?

    init(folder: URL, handler: @escaping @Sendable (Change) -> Void) {
        self.folder = folder
        self.handler = handler
    }

    deinit {
        // `stop()` is expected to have been called; this is a safety net.
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    @discardableResult
    func start() -> Bool {
        queue.sync {
            guard stream == nil else { return true }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)

            let flags = UInt32(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagWatchRoot
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagUseCFTypes)

            guard let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                folderWatcherCallback,
                &context,
                [folder.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.05,
                flags)
            else {
                Log.capture.error("FSEventStreamCreate failed for \(self.folder.path, privacy: .public)")
                return false
            }

            FSEventStreamSetDispatchQueue(created, queue)
            guard FSEventStreamStart(created) else {
                Log.capture.error("FSEventStreamStart failed for \(self.folder.path, privacy: .public)")
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
                return false
            }
            stream = created
            return true
        }
    }

    func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    /// Called on `queue`.
    fileprivate func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        var files: [String] = []
        var rootChanged = false
        var needsRescan = false

        for (path, flag) in zip(paths, flags) {
            let flag = Int(flag)
            if flag & kFSEventStreamEventFlagRootChanged != 0 {
                rootChanged = true
                continue
            }
            if flag & (kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped) != 0 {
                needsRescan = true
            }
            let interesting = kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRenamed
                | kFSEventStreamEventFlagItemModified
            if flag & kFSEventStreamEventFlagItemIsFile != 0, flag & interesting != 0 {
                files.append(path)
            }
        }

        if rootChanged { handler(.rootChanged) }
        if needsRescan { handler(.needsRescan) }
        if !files.isEmpty { handler(.files(files)) }
    }
}

private func folderWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    guard let paths = cfPaths as? [String] else { return }
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
    watcher.handle(paths: paths, flags: flags)
}
