import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusItem: StatusItemController?
    private var settingsWindow: HostedWindowController?
    private var onboardingWindow: HostedWindowController?
    private let systemDefaults = SystemDefaultsService()
    private lazy var integration = SystemIntegration(settings: settings, service: systemDefaults)
    private var updater: Updater?
    private let history = ClipboardHistory()
    private lazy var historyPanel = HistoryPanelController(history: history, settings: settings)
    private let hotKey = HotKey()
    private var registeredShortcut: HistoryShortcut?
    private var coordinator: CaptureCoordinator?
    private lazy var preview = NotchPreviewController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Dropshot launched")

        statusItem = StatusItemController(actions: .init(
            openSettings: { [weak self] in self?.showSettings() },
            openFolder: { [weak self] in self?.openScreenshotsFolder() },
            showHistory: { [weak self] in self?.historyPanel.show() },
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

        // Created at launch so Sparkle (when configured) can run its scheduled checks.
        updater = Updater()

        syncHistory()
        refreshStatusItem()
        coordinator?.sync()

        if !settings.onboardingCompleted {
            showOnboarding()
        }

        #if DEBUG
        // `-debugShowHistory YES`: open the clipboard panel shortly after launch (TESTING.md).
        if UserDefaults.standard.bool(forKey: "debugShowHistory") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.historyPanel.show() }
        }
        #endif
    }

    private func handle(_ capture: ProcessedCapture) {
        guard capture.isLive else { return }
        var copied = false
        if settings.copyToClipboard {
            copied = ClipboardWriter.write(capture)
            // The quality bar is "on the clipboard within 1 s of the file being written".
            if copied, let written = FileFlags.info(atPath: capture.url.path)?.modified {
                let ms = Int(Date().timeIntervalSince(written) * 1000)
                Log.capture.info("Clipboard ready \(ms) ms after \(capture.url.lastPathComponent, privacy: .public) was written")
            }
        }
        preview.show(capture, copied: copied)
        if settings.playSound {
            NSSound(named: "Pop")?.play()
        }
    }

    /// Launching the app again (Finder, Spotlight) is the way back in when the menu bar
    /// icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func settingsChanged() {
        integration.refresh()
        syncHistory()
        refreshStatusItem()
        coordinator?.sync()
    }

    /// Clipboard history follows its setting and the Pause switch.
    private func syncHistory() {
        let enabled = settings.historyEnabled && !settings.paused
        if enabled {
            history.start()
            if registeredShortcut != settings.historyShortcut {
                hotKey.register(settings.historyShortcut) { [weak self] in self?.historyPanel.toggle() }
                registeredShortcut = settings.historyShortcut
            }
        } else {
            history.stop()
            hotKey.unregister()
            registeredShortcut = nil
            historyPanel.hide()
            if !settings.historyEnabled { history.clear() }
        }
        statusItem?.historyTitle = enabled
            ? "Clipboard History (\(settings.historyShortcut.displayName))" : nil
    }

    private func refreshStatusItem() {
        statusItem?.update(
            visible: settings.showMenuBarIcon,
            paused: settings.paused,
            statusText: integration.statusText)
    }

    private func showSettings() {
        // Until setup is finished there is nothing meaningful to configure.
        guard settings.onboardingCompleted else {
            showOnboarding()
            return
        }
        if settingsWindow == nil {
            let updater = self.updater ?? Updater()
            self.updater = updater
            settingsWindow = HostedWindowController(title: "Dropshot Settings") { [settings, integration] in
                AnyView(SettingsView(settings: settings, integration: integration, updater: updater))
            }
            settingsWindow?.onClose = { [weak self] in self?.refreshStatusItem() }
        }
        integration.refresh()
        settingsWindow?.show()
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = HostedWindowController(title: "Welcome to Dropshot") { [weak self, settings, integration] in
                AnyView(OnboardingView(settings: settings, integration: integration) {
                    self?.finishOnboarding()
                })
            }
        }
        onboardingWindow?.show()
    }

    private func finishOnboarding() {
        // Flipping this starts the watchers (via the settings-changed notification).
        settings.onboardingCompleted = true
        onboardingWindow?.close()
        onboardingWindow = nil
        Log.app.info("Onboarding finished")
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
