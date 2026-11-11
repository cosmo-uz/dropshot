import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

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

        refreshStatusItem()
    }

    /// Launching the app again (Finder, Spotlight) is the way back in when the menu bar
    /// icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func settingsChanged() {
        refreshStatusItem()
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
