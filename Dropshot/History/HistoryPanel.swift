import AppKit
import ApplicationServices
import DropshotCore
import Observation
import SwiftUI

@MainActor
@Observable
final class HistoryPanelModel {
    var selection = 0
    var isShown = false
    var hint = ""
}

/// Borderless panel that can take keyboard input without activating Dropshot, so the app
/// you were typing in stays frontmost and receives the paste.
final class HistoryWindow: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        resignKey()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Shows the clipboard history under the notch and handles picking an entry.
@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let history: ClipboardHistory
    private let settings: AppSettings
    private let model = HistoryPanelModel()
    private var window: HistoryWindow?

    static let size = CGSize(width: 400, height: 420)

    init(history: ClipboardHistory, settings: AppSettings) {
        self.history = history
        self.settings = settings
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let screens = NSScreen.screens
        let screen = NotchGeometry.screenIndex(containing: NSEvent.mouseLocation, frames: screens.map(\.frame))
            .map { screens[$0] } ?? NSScreen.main
        guard let screen else { return }

        let window = self.window ?? makeWindow()
        self.window = window

        let description = screen.islandDescription
        let top = screen.frame.maxY - max(description.safeAreaTop, description.menuBarHeight) - 6
        let size = Self.size
        window.setFrame(
            CGRect(x: (screen.frame.midX - size.width / 2).rounded(), y: top - size.height,
                   width: size.width, height: size.height),
            display: true)

        model.selection = 0
        model.hint = settings.pasteDirectly && !AXIsProcessTrusted()
            ? "Allow Accessibility for Dropshot to paste directly"
            : (settings.pasteDirectly ? "↩ paste  ·  1–9 quick pick  ·  ⌫ remove  ·  esc close"
                                      : "↩ copy  ·  1–9 quick pick  ·  ⌫ remove  ·  esc close")
        window.makeKeyAndOrderFront(nil)
        if ScreenLocator.reduceMotion {
            model.isShown = true
        } else {
            model.isShown = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { model.isShown = true }
        }
    }

    func hide() {
        guard let window, window.isVisible else { return }
        model.isShown = false
        window.orderOut(nil)
    }

    private func makeWindow() -> HistoryWindow {
        let window = HistoryWindow()
        window.delegate = self
        window.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        let view = HistoryView(
            history: history, model: model,
            onPick: { [weak self] in self?.pick($0) },
            onClear: { [weak self] in self?.history.clear() })
        let hosting = FirstMouseHostingView(rootView: view)
        window.contentView = hosting
        return window
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let count = history.items.count
        switch Int(event.keyCode) {
        case 53: // esc
            hide()
        case 125: // down
            if count > 0 { model.selection = min(model.selection + 1, count - 1) }
        case 126: // up
            if count > 0 { model.selection = max(model.selection - 1, 0) }
        case 36, 76: // return, enter
            if history.items.indices.contains(model.selection) { pick(history.items[model.selection]) }
        case 51, 117: // delete
            if history.items.indices.contains(model.selection) {
                history.remove(history.items[model.selection])
                model.selection = max(0, min(model.selection, history.items.count - 1))
            }
        default:
            if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit),
               history.items.indices.contains(digit - 1) {
                pick(history.items[digit - 1])
            } else {
                return false
            }
        }
        return true
    }

    private func pick(_ item: ClipItem) {
        history.copy(item)
        hide()
        guard settings.pasteDirectly, AXIsProcessTrusted() else { return }
        // Give the previous app a moment to be key again, then press ⌘V for the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyV = CGKeyCode(9)
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Asks macOS for the Accessibility permission that pasting on the user's behalf needs.
    static func requestPastePermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

// MARK: - View

struct HistoryView: View {
    let history: ClipboardHistory
    let model: HistoryPanelModel
    var onPick: (ClipItem) -> Void = { _ in }
    var onClear: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0) {
            HStack {
                Text("Clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !history.items.isEmpty {
                    Button("Clear", action: onClear)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if history.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Nothing copied yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Text, images and files you copy will show up here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(history.items.enumerated()), id: \.element.id) { index, item in
                                HistoryRow(item: item, index: index, selected: index == model.selection)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onPick(item) }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .onChange(of: model.selection) { _, selection in
                        if history.items.indices.contains(selection) {
                            proxy.scrollTo(history.items[selection].id)
                        }
                    }
                }
            }

            Text(model.hint)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .scaleEffect(model.isShown ? 1 : 0.6, anchor: .top)
        .opacity(model.isShown ? 1 : 0)
        .accessibilityLabel("Clipboard history")
    }
}

private struct HistoryRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.1)
                        Image(systemName: item.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(width: 44, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.85) : .clear))
    }
}
