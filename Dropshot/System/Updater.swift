import Foundation
import Observation
@preconcurrency import Sparkle

/// Thin wrapper around Sparkle — the only code in Dropshot that can touch the network.
///
/// Sparkle is started only when the build carries both a feed URL and an EdDSA public key
/// (see RELEASING.md). A development build has neither, so it makes no network calls at all.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? ""
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? ""
        let configured = !feed.isEmpty && !key.isEmpty && URL(string: feed)?.scheme == "https"
        isConfigured = configured
        if configured {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            Log.app.info("Sparkle updater started")
        } else {
            controller = nil
            Log.app.info("Sparkle not configured — updater disabled, no network access")
        }
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
