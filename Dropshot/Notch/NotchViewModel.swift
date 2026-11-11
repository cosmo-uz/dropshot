import AppKit
import DropshotCore
import Observation

/// One capture shown in the island.
struct PreviewItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let kind: CaptureKind
    let thumbnail: NSImage?
    let pixelSize: CGSize?
    let duration: TimeInterval?
    /// Whether it was put on the clipboard (drives the "Copied ✓" label).
    let copied: Bool

    static func == (lhs: PreviewItem, rhs: PreviewItem) -> Bool { lhs.id == rhs.id }

    var statusText: String {
        switch (kind, copied) {
        case (.image, true): "Copied ✓"
        case (.recording, true): "File copied ✓"
        case (_, false): "Saved ✓"
        }
    }

    var detailText: String {
        var parts: [String] = []
        if let pixelSize {
            parts.append("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
        }
        if let duration {
            let seconds = Int(duration.rounded())
            parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        if parts.isEmpty { parts.append(kind == .image ? "Screenshot" : "Recording") }
        return parts.joined(separator: " · ")
    }
}

/// State the island's SwiftUI views render from. Mutated only by `NotchPreviewController`.
@MainActor
@Observable
final class NotchViewModel {
    /// Newest first.
    var items: [PreviewItem] = []
    var isExpanded = false
    var isHovering = false
    var layout: IslandLayout
    var reduceMotion = false
    /// Offscreen rendering only: skips the AppKit-backed hover / drag helpers.
    var isStatic = false

    @ObservationIgnored var onHoverChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var onOpen: (PreviewItem) -> Void = { _ in }
    @ObservationIgnored var onReveal: (PreviewItem) -> Void = { _ in }
    @ObservationIgnored var onDelete: (PreviewItem) -> Void = { _ in }
    @ObservationIgnored var onDragBegan: (PreviewItem) -> Void = { _ in }
    @ObservationIgnored var onDragEnded: (PreviewItem, Bool) -> Void = { _, _ in }

    init(layout: IslandLayout) {
        self.layout = layout
    }

    var top: PreviewItem? { items.first }
}
