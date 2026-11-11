import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private let systemDefaults = SystemDefaultsService()
    private var coordinator: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Dropshot launched")

        statusItem = StatusItemController(actions: .init(
            openSettings: { [weak self] in self?.showSettings() },
            openFolder: { [weak self] in self?.openScreenshotsFolder() },
            togglePause: { [weak self] in self?.settings.paused.toggle() },
            quit: { NSApp.terminate(nil) }
        ))

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .dropshotSettingsChanged, object: nil)

        coordinator = CaptureCoordinator(
            settings: settings,
            customNamePrefix: { [systemDefaults] in systemDefaults.customNamePrefix },
            onCapture: { [weak self] in self?.handle($0) })

        refreshStatusItem()
        coordinator?.sync()
    }

    private func handle(_ capture: ProcessedCapture) {
        guard capture.isLive else { return }
        if settings.copyToClipboard, ClipboardWriter.write(capture) {
            // The quality bar is "on the clipboard within 1 s of the file being written".
            if let written = FileFlags.info(atPath: capture.url.path)?.modified {
                let ms = Int(Date().timeIntervalSince(written) * 1000)
                Log.capture.info("Clipboard ready \(ms) ms after \(capture.url.lastPathComponent, privacy: .public) was written")
            }
        }
    }

    /// Launching the app again (Finder, Spotlight) is the way back in when the menu bar
    /// icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func settingsChanged() {
        refreshStatusItem()
        coordinator?.sync()
    }

    private func refreshStatusItem() {
        statusItem?.update(
            visible: settings.showMenuBarIcon,
            paused: settings.paused,
            statusText: settings.paused ? "Paused" : "Watching for screenshots")
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController { [settings] in
                AnyView(SettingsView(settings: settings))
            }
        }
        settingsWindow?.show()
    }

    private func openScreenshotsFolder() {
        let folder = settings.rootFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.app.error("Could not create \(folder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        NSWorkspace.shared.open(folder)
    }
}
