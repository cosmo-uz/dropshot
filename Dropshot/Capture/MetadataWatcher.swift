import Foundation

/// Backup detector: a live Spotlight query for `kMDItemIsScreenCapture` inside the root
/// folder. If FSEvents ever misses a capture, Spotlight reports it a moment later and the
/// pipeline's de-duplication makes the double report harmless.
@MainActor
final class MetadataWatcher: NSObject {
    private var query: NSMetadataQuery?
    private let folder: URL
    private let handler: ([String]) -> Void

    init(folder: URL, handler: @escaping ([String]) -> Void) {
        self.folder = folder
        self.handler = handler
        super.init()
    }

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [folder]
        query.notificationBatchingInterval = 0.2
        query.operationQueue = .main
        NotificationCenter.default.addObserver(
            self, selector: #selector(didUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: query)
        if !query.start() {
            Log.capture.notice("Spotlight query could not start (indexing disabled?) — FSEvents only")
        }
        self.query = query
    }

    func stop() {
        guard let query else { return }
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        query.stop()
        self.query = nil
    }

    @objc private func didUpdate(_ notification: Notification) {
        // Only *added* items matter; pre-existing files are handled by the startup sweep.
        guard let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]
        else { return }
        let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
        if !paths.isEmpty { handler(paths) }
    }
}
