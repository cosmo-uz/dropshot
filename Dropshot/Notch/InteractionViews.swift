import AppKit
import DropshotCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Hover

/// SwiftUI's `onHover` only fires while the app is active — and an agent app never is.
/// This uses an always-active tracking area instead.
struct HoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private var isInside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
            // The island may have grown under (or shrunk away from) a stationary pointer.
            guard let window else { return }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            set(inside: bounds.contains(point))
        }

        override func mouseEntered(with event: NSEvent) { set(inside: true) }
        override func mouseExited(with event: NSEvent) { set(inside: false) }

        private func set(inside: Bool) {
            guard inside != isInside else { return }
            isInside = inside
            onChange(inside)
        }
    }
}

// MARK: - Drag out

/// Transparent overlay on the thumbnail that starts a real AppKit drag carrying the
/// capture as a file URL (plus image data), so it can be dropped into Finder, Telegram,
/// Slack, browsers, Figma… A plain click opens the file.
struct DragSource: NSViewRepresentable {
    var item: PreviewItem
    var onClick: () -> Void
    var onBegan: () -> Void
    var onEnded: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: DragSourceView) {
        view.item = item
        view.onClick = onClick
        view.onBegan = onBegan
        view.onEnded = onEnded
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var item: PreviewItem?
    var onClick: () -> Void = {}
    var onBegan: () -> Void = {}
    var onEnded: (Bool) -> Void = { _ in }

    private var mouseDownEvent: NSEvent?
    private var isDragging = false
    // Kept alive for the duration of the drag; the pasteboard only holds it weakly.
    private var imageProvider: LazyImageProvider?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        if !isDragging, mouseDownEvent != nil { onClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let down = mouseDownEvent, let item else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy >= 9 else { return }
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            Log.notch.notice("Drag skipped: \(item.url.lastPathComponent, privacy: .public) no longer exists")
            return
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        if item.kind == .image {
            let provider = LazyImageProvider(url: item.url)
            pasteboardItem.setDataProvider(provider, forTypes: [.png, .tiff])
            imageProvider = provider
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = item.thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path)
        draggingItem.setDraggingFrame(Self.aspectFit(image.size, in: bounds), contents: image)

        isDragging = true
        onBegan()
        let session = beginDraggingSession(with: [draggingItem], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
            width: fitted.width, height: fitted.height)
    }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Copy only: the original always stays in the Screenshots folder.
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        mouseDownEvent = nil
        imageProvider = nil
        onEnded(operation != [])
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
