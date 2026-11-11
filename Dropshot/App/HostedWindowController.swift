import AppKit
import SwiftUI

/// Hosts a SwiftUI view in a regular window (Settings, onboarding). The window and its
/// view tree are released when closed, so an idle Dropshot holds no UI in memory.
@MainActor
final class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> AnyView
    var onClose: (() -> Void)?

    var isOpen: Bool { window != nil }

    init(title: String, makeContent: @escaping () -> AnyView) {
        self.title = title
        self.makeContent = makeContent
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        onClose?()
    }
}
