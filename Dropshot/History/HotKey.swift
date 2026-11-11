import AppKit
import Carbon.HIToolbox

/// The choices offered for the clipboard-history shortcut.
enum HistoryShortcut: String, CaseIterable, Identifiable {
    case commandShiftV
    case controlCommandV
    case optionCommandV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandShiftV: "⇧⌘V"
        case .controlCommandV: "⌃⌘V"
        case .optionCommandV: "⌥⌘V"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandShiftV: UInt32(cmdKey | shiftKey)
        case .controlCommandV: UInt32(cmdKey | controlKey)
        case .optionCommandV: UInt32(cmdKey | optionKey)
        }
    }
}

/// A single system-wide hot key (Carbon `RegisterEventHotKey` — the one global-shortcut API
/// that needs no Accessibility or Input Monitoring permission).
@MainActor
final class HotKey {
    private static var action: (() -> Void)?
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?

    private static func fire() { action?() }

    func register(_ shortcut: HistoryShortcut, action: @escaping () -> Void) {
        unregister()
        Self.action = action

        if !Self.handlerInstalled {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, _ in
                    Task { @MainActor in HotKey.fire() }
                    return noErr
                },
                1, &spec, nil, nil)
            guard status == noErr else {
                Log.app.error("Could not install hot key handler (\(status))")
                return
            }
            Self.handlerInstalled = true
        }

        let id = EventHotKeyID(signature: OSType(0x4453_4854) /* 'DSHT' */, id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &newRef)
        if status == noErr {
            ref = newRef
            Log.app.info("Clipboard history shortcut: \(shortcut.displayName, privacy: .public)")
        } else {
            Log.app.error("Could not register \(shortcut.displayName, privacy: .public) (\(status)) — another app may own it")
        }
    }

    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
    }
}
