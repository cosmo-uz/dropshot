import CoreGraphics
import Foundation

/// The parts of an `NSScreen` the island math needs (AppKit coordinates, origin bottom-left).
public struct ScreenDescription: Sendable, Equatable {
    public var frame: CGRect
    /// `NSScreen.safeAreaInsets.top` — the notch height, 0 on screens without one.
    public var safeAreaTop: CGFloat
    /// Width of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, `nil` when absent.
    public var auxiliaryTopLeftWidth: CGFloat?
    public var auxiliaryTopRightWidth: CGFloat?
    /// `frame.maxY - visibleFrame.maxY`; 0 when the menu bar is hidden (fullscreen).
    public var menuBarHeight: CGFloat

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftWidth: CGFloat? = nil,
        auxiliaryTopRightWidth: CGFloat? = nil,
        menuBarHeight: CGFloat = 0
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
        self.menuBarHeight = menuBarHeight
    }
}

public enum IslandStyle: Sendable, Equatable {
    /// Grows out of the hardware notch.
    case notch
    /// Floating pill at top centre (no notch, or external display).
    case pill
}

/// Everything needed to place and animate the island on one screen.
public struct IslandLayout: Sendable, Equatable {
    public var style: IslandStyle
    /// Idle size. In notch style this is exactly the hardware notch, so it is invisible.
    public var collapsedSize: CGSize
    public var expandedSize: CGSize
    /// Height at the top of the expanded island hidden behind the notch (0 for a pill).
    public var topInset: CGFloat
    /// 1 normally, smaller when a fullscreen app is in front.
    public var scale: CGFloat
    /// Frame of the transparent host window, in screen coordinates. The island is pinned to
    /// its top-centre; the margin leaves room for the shadow.
    public var windowFrame: CGRect
}

public enum NotchGeometry {
    public static let expandedContentSize = CGSize(width: 360, height: 100)
    public static let compactScale: CGFloat = 0.75
    public static let pillCollapsedSize = CGSize(width: 96, height: 6)
    public static let pillTopMargin: CGFloat = 8
    public static let windowSideMargin: CGFloat = 28
    public static let windowBottomMargin: CGFloat = 40
    /// How far the expanded island must extend past each side of the notch.
    public static let minimumNotchOverhang: CGFloat = 40

    /// The hardware notch in screen coordinates, or `nil` if this screen has none.
    public static func notchRect(for screen: ScreenDescription) -> CGRect? {
        guard screen.safeAreaTop > 0,
              let left = screen.auxiliaryTopLeftWidth,
              let right = screen.auxiliaryTopRightWidth
        else { return nil }
        let width = screen.frame.width - left - right
        guard width > 0, left > 0, right > 0 else { return nil }
        return CGRect(
            x: screen.frame.minX + left,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop)
    }

    public static func layout(for screen: ScreenDescription, compact: Bool = false) -> IslandLayout {
        let scale = compact ? compactScale : 1
        let content = CGSize(
            width: (expandedContentSize.width * scale).rounded(),
            height: (expandedContentSize.height * scale).rounded())

        let style: IslandStyle
        let collapsed: CGSize
        let expanded: CGSize
        let topInset: CGFloat
        let centerX: CGFloat
        let top: CGFloat

        if let notch = notchRect(for: screen) {
            style = .notch
            collapsed = notch.size
            topInset = notch.height
            expanded = CGSize(
                width: max(content.width, notch.width + 2 * (minimumNotchOverhang * scale).rounded()),
                height: notch.height + content.height)
            centerX = notch.midX
            top = screen.frame.maxY
        } else {
            style = .pill
            collapsed = pillCollapsedSize
            topInset = 0
            expanded = content
            centerX = screen.frame.midX
            top = screen.frame.maxY - max(0, screen.menuBarHeight) - pillTopMargin
        }

        // Never wider than the screen itself (tiny or portrait displays).
        let maxWidth = max(collapsed.width, screen.frame.width - 2 * windowSideMargin)
        let clamped = CGSize(width: min(expanded.width, maxWidth), height: expanded.height)

        let windowSize = CGSize(
            width: clamped.width + 2 * windowSideMargin,
            height: clamped.height + windowBottomMargin)
        let window = CGRect(
            x: (centerX - windowSize.width / 2).rounded(),
            y: (top - windowSize.height).rounded(),
            width: windowSize.width,
            height: windowSize.height)

        return IslandLayout(
            style: style,
            collapsedSize: collapsed,
            expandedSize: clamped,
            topInset: topInset,
            scale: scale,
            windowFrame: window)
    }

    /// Index of the screen whose frame contains `point` (e.g. the mouse location).
    public static func screenIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
        // NSScreen frames are half-open at the top/right edges; be generous by 1pt.
        frames.firstIndex { $0.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// True when one of `windowBounds` (normal-layer windows, CoreGraphics display
    /// coordinates) covers the whole display — i.e. an app is in native fullscreen there.
    ///
    /// On notched displays a fullscreen window stops below the notch, which is also what a
    /// zoomed window with a hidden Dock looks like. That case only counts as fullscreen
    /// when the menu bar is not showing.
    public static func isFullscreen(
        windowBounds: [CGRect],
        displayBounds: CGRect,
        topInset: CGFloat = 0,
        menuBarVisible: Bool = false,
        tolerance: CGFloat = 1
    ) -> Bool {
        windowBounds.contains { window in
            guard abs(window.minX - displayBounds.minX) <= tolerance,
                  abs(window.width - displayBounds.width) <= tolerance,
                  abs(window.maxY - displayBounds.maxY) <= tolerance
            else { return false }
            if window.height >= displayBounds.height - tolerance { return true }
            guard topInset > 0, !menuBarVisible else { return false }
            return window.height >= displayBounds.height - topInset - tolerance
        }
    }
}
