import AppKit
import DropshotCore

extension NSScreen {
    var islandDescription: ScreenDescription {
        ScreenDescription(
            frame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width,
            menuBarHeight: max(0, frame.maxY - visibleFrame.maxY))
    }
}

/// Decides where the island goes. (Milestone 3: always the main screen.)
@MainActor
enum ScreenLocator {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func captureRect(of url: URL) -> CGRect? { nil }

    static func screen(forCaptureRect rect: CGRect?) -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    static func layout(for screen: NSScreen) -> IslandLayout {
        NotchGeometry.layout(for: screen.islandDescription)
    }
}
