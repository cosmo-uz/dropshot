import DropshotCore
import Foundation
import ImageIO

/// A capture that has been sorted into its final location.
struct ProcessedCapture: Sendable, Identifiable {
    let id = UUID()
    let url: URL
    let kind: CaptureKind
    let date: Date
    /// `false` for captures found during a catch-up sweep: they are sorted silently,
    /// without touching the clipboard or showing a preview.
    let isLive: Bool
}

/// detect → wait until fully written → de-duplicate → move into the dated folder → report.
actor CapturePipeline {
    struct Config: Sendable, Equatable {
        var root: URL
        var folderPattern: FolderPattern
        var renamePattern: RenamePattern
        /// `defaults read com.apple.screencapture name`, if the user customised it.
        var customNamePrefix: String?
    }

    private var config: Config
    private let onCapture: @Sendable (ProcessedCapture) async -> Void
    private var inFlight: Set<String> = []
    private var handled = EventDeduplicator<String>(ttl: 600, capacity: 1024)

    init(config: Config, onCapture: @escaping @Sendable (ProcessedCapture) async -> Void) {
        self.config = config
        self.onCapture = onCapture
    }

    func update(config: Config) {
        self.config = config
    }

    /// Entry point for FSEvents and Spotlight reports. Safe to call repeatedly for one file.
    nonisolated func ingest(paths: [String], live: Bool = true) {
        for path in paths {
            Task { await self.process(path: path, live: live) }
        }
    }

    /// Handles whatever is sitting in the root folder right now.
    /// - Parameter live: `false` sorts flagged captures silently (startup, resume);
    ///   `true` treats fresh ones as just taken (after dropped events or wake).
    func sweep(live: Bool) {
        let root = config.root
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        let paths = names
            .filter { CaptureClassifier.kind(forFileName: $0) != nil }
            .map { root.appendingPathComponent($0).path }
        guard !paths.isEmpty else { return }
        Log.capture.debug("Sweep (live: \(live)) found \(paths.count) candidate(s)")
        for path in paths {
            Task { await self.process(path: path, live: live) }
        }
    }

    // MARK: -

    private func process(path: String, live: Bool) async {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let name = url.lastPathComponent
        let config = self.config

        guard CaptureClassifier.isDirectChild(url, of: config.root),
              let kind = CaptureClassifier.kind(forFileName: name)
        else { return }

        let key = url.path
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        // 1. Wait until the file has stopped growing.
        let tracker = StabilityTracker(
            requiredStableReads: kind == .image ? 2 : 4,
            missingTolerance: 3,
            timeout: 120)
        let verdict = await FileStability.waitUntilStable(
            tracker: tracker,
            pollInterval: .milliseconds(kind == .image ? 100 : 250),
            size: { FileStability.fileSize(atPath: key) })
        guard case .stable = verdict else {
            if verdict == .timedOut {
                Log.capture.error("Gave up waiting for \(name, privacy: .public) to finish writing")
            }
            return
        }

        // 2. Is it really a capture, and have we seen it already?
        guard let info = FileFlags.info(atPath: key) else { return }
        guard !FileFlags.has(FileFlags.processed, atPath: key) else { return }
        let isCapture = CaptureClassifier.isCapture(
            fileName: name,
            hasScreenCaptureFlag: FileFlags.has(FileFlags.screenCapture, atPath: key),
            lastWritten: max(info.created, info.modified),
            now: Date(),
            live: live,
            customPrefix: config.customNamePrefix)
        guard isCapture else { return }

        // 3. Images must also decode completely (size can be stable mid-write on slow volumes).
        if kind == .image, !(await waitUntilDecodable(url)) {
            Log.capture.error("\(name, privacy: .public) never became a readable image; leaving it in place")
            return
        }

        guard handled.shouldProcess(info.identity, at: ProcessInfo.processInfo.systemUptime) else { return }

        // 4. Sort it.
        let finalURL = move(url, date: info.created, config: config)
        FileFlags.set(FileFlags.processed, atPath: finalURL.path)

        Log.capture.info("Sorted \(name, privacy: .public) → \(finalURL.path, privacy: .public)")
        await onCapture(ProcessedCapture(url: finalURL, kind: kind, date: info.created, isLive: live))
    }

    /// Polls for up to ~30 s: a writer that paused mid-file gets time to finish.
    private func waitUntilDecodable(_ url: URL) async -> Bool {
        for _ in 0..<300 {
            if Self.isCompleteImage(url) { return true }
            if FileStability.fileSize(atPath: url.path) == nil { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static func isCompleteImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        // PNG / JPEG: the trailer must be present, otherwise the file is still being written.
        if let tail = ImageCompleteness.tail(ofFileAtPath: url.path),
           let complete = ImageCompleteness.isComplete(fileExtension: ext, tail: tail),
           !complete {
            return false
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetStatus(source) == .statusComplete && CGImageSourceGetCount(source) > 0
    }

    /// Moves `url` to its planned destination. On any failure the file is left where it is —
    /// a capture is never lost because sorting failed.
    private func move(_ url: URL, date: Date, config: Config) -> URL {
        let fileManager = FileManager.default
        let planner = PathPlanner(
            root: config.root,
            folderPattern: config.folderPattern,
            renamePattern: config.renamePattern)

        let directory = planner.directory(for: date)
        let plannedName = planner.fileName(originalName: url.lastPathComponent, date: date)
        if directory.appendingPathComponent(plannedName).standardizedFileURL.path == url.path {
            return url // already exactly where it belongs (flat folder, original name)
        }

        let destination = planner.destination(originalName: url.lastPathComponent, date: date) {
            fileManager.fileExists(atPath: $0.path)
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: destination)
            return destination
        } catch {
            Log.capture.error("Could not move \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return url
        }
    }
}
