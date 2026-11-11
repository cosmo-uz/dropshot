import AppKit
import DropshotCore
import SwiftUI

/// Drives the island: shows it for each capture, stacks rapid captures, keeps it open
/// while hovered or dragged, and tucks it back into the notch afterwards.
@MainActor
final class NotchPreviewController {
    private let settings: AppSettings
    private var panel: NotchPanel?
    private var model: NotchViewModel?

    private var dismissTask: Task<Void, Never>?
    /// Bumped whenever the island is (re)opened, so a stale collapse cannot hide a new preview.
    private var generation = 0
    private var isCollapsing = false
    private var isDragging = false
    private var screenObserver: NSObjectProtocol?

    private static let maxStack = 20

    init(settings: AppSettings) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: Showing

    func show(_ capture: ProcessedCapture, copied: Bool) {
        Task {
            let result = await Thumbnailer.make(for: capture.url, kind: capture.kind)
            let item = PreviewItem(
                id: capture.id,
                url: capture.url,
                kind: capture.kind,
                thumbnail: result.image.map { NSImage(cgImage: $0, size: .zero) },
                pixelSize: result.pixelSize,
                duration: result.duration,
                copied: copied)
            present(item, sourceRect: ScreenLocator.captureRect(of: capture.url))
        }
    }

    private var animation: Animation {
        model?.reduceMotion == true
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.35, dampingFraction: 0.8)
    }

    private func present(_ item: PreviewItem, sourceRect: CGRect?) {
        if let model, isVisible, model.isExpanded, !isCollapsing {
            // Already open: stack the new capture on top.
            withAnimation(animation) {
                model.items.insert(item, at: 0)
                if model.items.count > Self.maxStack {
                    model.items.removeLast(model.items.count - Self.maxStack)
                }
            }
            scheduleDismiss()
            return
        }

        guard let screen = ScreenLocator.screen(forCaptureRect: sourceRect) else {
            Log.notch.error("No screen available for the preview")
            return
        }
        let layout = ScreenLocator.layout(for: screen)

        generation += 1
        let wasCollapsing = isCollapsing
        isCollapsing = false

        let model = self.model ?? makeModel(layout: layout)
        let panel = self.panel ?? makePanel(model: model)

        model.reduceMotion = ScreenLocator.reduceMotion
        model.layout = layout
        model.items = [item]
        if !wasCollapsing { model.isExpanded = false }

        panel.setFrame(layout.windowFrame, display: true)
        panel.orderFrontRegardless()

        // Let the collapsed state render once, then grow out of the notch.
        let opening = generation
        Task {
            try? await Task.sleep(for: .milliseconds(30))
            guard opening == self.generation else { return }
            withAnimation(self.animation) { model.isExpanded = true }
        }
        scheduleDismiss()
    }

    private func makeModel(layout: IslandLayout) -> NotchViewModel {
        let model = NotchViewModel(layout: layout)
        model.onHoverChanged = { [weak self] in self?.hoverChanged($0) }
        model.onOpen = { [weak self] in self?.open($0) }
        model.onReveal = { [weak self] in self?.reveal($0) }
        model.onDelete = { [weak self] in self?.delete($0) }
        model.onDragBegan = { [weak self] _ in self?.dragBegan() }
        model.onDragEnded = { [weak self] in self?.dragEnded($0, success: $1) }
        self.model = model
        return model
    }

    private func makePanel(model: NotchViewModel) -> NotchPanel {
        let panel = NotchPanel()
        let hosting = FirstMouseHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    // MARK: Dismissing

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard model?.isHovering != true, !isDragging else { return }
        let duration = settings.previewDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    func collapse() {
        dismissTask?.cancel()
        guard let model, isVisible, !isCollapsing else { return }
        isCollapsing = true
        let closing = generation

        withAnimation(animation, completionCriteria: .logicallyComplete) {
            model.isExpanded = false
        } completion: { [weak self] in
            Task { @MainActor in self?.finishCollapse(closing) }
        }
        // Safety net in case the completion never arrives (e.g. the display went away).
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.finishCollapse(closing)
        }
    }

    private func finishCollapse(_ closing: Int) {
        guard closing == generation, isCollapsing else { return }
        isCollapsing = false
        panel?.orderOut(nil)
        // Drop thumbnails so an idle Dropshot holds no image memory.
        model?.items = []
        model?.isHovering = false
    }

    /// Hides immediately, without animation.
    func hideNow() {
        dismissTask?.cancel()
        generation += 1
        isCollapsing = false
        isDragging = false
        panel?.orderOut(nil)
        model?.isExpanded = false
        model?.items = []
        model?.isHovering = false
    }

    // MARK: Interaction

    private func hoverChanged(_ hovering: Bool) {
        guard let model, model.isHovering != hovering else { return }
        model.isHovering = hovering
        if hovering {
            dismissTask?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func open(_ item: PreviewItem) {
        NSWorkspace.shared.open(item.url)
        remove(item)
    }

    private func reveal(_ item: PreviewItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        collapse()
    }

    private func delete(_ item: PreviewItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            Log.notch.info("Moved \(item.url.lastPathComponent, privacy: .public) to the Trash")
        } catch {
            Log.notch.error("Could not trash \(item.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return
        }
        remove(item)
    }

    private func dragBegan() {
        isDragging = true
        dismissTask?.cancel()
    }

    private func dragEnded(_ item: PreviewItem, success: Bool) {
        isDragging = false
        if success {
            remove(item)
        } else {
            scheduleDismiss()
        }
    }

    /// Takes one capture off the stack; the next one (if any) comes to the top.
    private func remove(_ item: PreviewItem) {
        guard let model else { return }
        if model.items.count <= 1 {
            collapse()
            return
        }
        withAnimation(animation) {
            model.items.removeAll { $0.id == item.id }
        }
        scheduleDismiss()
    }

    // MARK: Displays

    /// A display was connected, removed or rearranged while the island is up.
    private func screensChanged() {
        guard isVisible, let panel, let model else { return }
        // Follow the screen the island is on; if it vanished, just close.
        let current = NSScreen.screens.first { $0.frame.intersects(panel.frame) }
        guard let current else {
            hideNow()
            return
        }
        let layout = ScreenLocator.layout(for: current)
        model.layout = layout
        panel.setFrame(layout.windowFrame, display: true)
    }
}
