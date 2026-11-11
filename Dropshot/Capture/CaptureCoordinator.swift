import AppKit
import DropshotCore
import Foundation

/// Owns the watchers and the pipeline, and keeps them alive across everything that can
/// go wrong underneath them: the folder disappearing, sleep/wake, settings changes.
@MainActor
final class CaptureCoordinator {
    private let settings: AppSettings
    private let customNamePrefix: () -> String?
    private let onCapture: (ProcessedCapture) -> Void

    private var pipeline: CapturePipeline?
    private var watcher: FolderWatcher?
    private var metadataWatcher: MetadataWatcher?
    private var watchedRoot: URL?
    private var wakeObserver: NSObjectProtocol?

    private(set) var isRunning = false

    init(
        settings: AppSettings,
        customNamePrefix: @escaping () -> String?,
        onCapture: @escaping (ProcessedCapture) -> Void
    ) {
        self.settings = settings
        self.customNamePrefix = customNamePrefix
        self.onCapture = onCapture

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
    }

    private var config: CapturePipeline.Config {
        .init(
            root: settings.rootFolder,
            folderPattern: settings.folderPattern,
            renamePattern: settings.renamePattern,
            customNamePrefix: customNamePrefix())
    }

    /// Brings the running state in line with the settings. Call after any settings change.
    func sync(liveSweep: Bool = false) {
        let shouldRun = !settings.paused && settings.onboardingCompleted
        if !shouldRun {
            stop()
            return
        }
        if isRunning, watchedRoot == settings.rootFolder {
            let config = self.config
            if let pipeline { Task { await pipeline.update(config: config) } }
            return
        }
        stop()
        start(liveSweep: liveSweep)
    }

    private func start(liveSweep: Bool) {
        let root = settings.rootFolder
        guard ensureFolderExists(root) else { return }

        let pipeline = CapturePipeline(config: config) { [weak self] capture in
            await self?.deliver(capture)
        }
        self.pipeline = pipeline

        let watcher = FolderWatcher(folder: root) { [weak self] change in
            switch change {
            case .files(let paths):
                pipeline.ingest(paths: paths)
            case .needsRescan:
                Task { await pipeline.sweep(live: true) }
            case .rootChanged:
                Task { @MainActor in self?.handleRootChanged() }
            }
        }
        guard watcher.start() else { return }
        self.watcher = watcher

        let metadata = MetadataWatcher(folder: root) { paths in
            pipeline.ingest(paths: paths)
        }
        metadata.start()
        metadataWatcher = metadata

        watchedRoot = root
        isRunning = true
        Log.capture.info("Watching \(root.path, privacy: .public)")

        // Anything captured while we were not running gets sorted quietly; after a wake or a
        // folder hiccup, fresh captures still get the full treatment.
        Task { await pipeline.sweep(live: liveSweep) }
    }

    func stop() {
        guard isRunning || watcher != nil else { return }
        watcher?.stop()
        watcher = nil
        metadataWatcher?.stop()
        metadataWatcher = nil
        pipeline = nil
        watchedRoot = nil
        isRunning = false
        Log.capture.info("Stopped watching")
    }

    private func deliver(_ capture: ProcessedCapture) {
        onCapture(capture)
    }

    /// The folder was deleted, renamed or moved out from under us: put it back and carry on.
    private func handleRootChanged() {
        guard isRunning, let root = watchedRoot else { return }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
        Log.capture.notice("Screenshots folder changed on disk (exists: \(exists)) — re-establishing")
        stop()
        // `sync` recreates the folder and restarts both watchers.
        sync(liveSweep: true)
    }

    private func handleWake() {
        guard isRunning else { return }
        Log.capture.info("Woke from sleep — restarting watchers")
        stop()
        // A capture taken in the instant around sleep is still fresh; treat it as live.
        sync(liveSweep: true)
    }

    private func ensureFolderExists(_ folder: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return true
        } catch {
            Log.capture.error("Cannot create \(folder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
