import AppKit

/// The small menu bar icon: Settings…, Open Screenshots Folder, Pause, Quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var openSettings: () -> Void
        var openFolder: () -> Void
        var togglePause: () -> Void
        var quit: () -> Void
    }

    private var statusItem: NSStatusItem?
    private let actions: Actions
    private var isPaused = false
    private var statusText = ""

    init(actions: Actions) {
        self.actions = actions
        super.init()
    }

    func update(visible: Bool, paused: Bool, statusText: String) {
        isPaused = paused
        self.statusText = statusText
        if visible {
            if statusItem == nil { install() }
            refreshIcon()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = isPaused ? "pause.circle" : "camera.viewfinder"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Dropshot")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = isPaused
        button.toolTip = isPaused ? "Dropshot (paused)" : "Dropshot"
    }

    // Rebuilt lazily each time it opens so titles always reflect current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Open Screenshots Folder", #selector(openFolder), key: "o"))
        menu.addItem(item(isPaused ? "Resume" : "Pause", #selector(togglePause), key: "p"))
        menu.addItem(.separator())
        menu.addItem(item("Quit Dropshot", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { actions.openSettings() }
    @objc private func openFolder() { actions.openFolder() }
    @objc private func togglePause() { actions.togglePause() }
    @objc private func quit() { actions.quit() }
}
