import AppKit
import DropshotCore

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var islandDescription: ScreenDescription {
        ScreenDescription(
            frame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width,
            menuBarHeight: max(0, frame.maxY - visibleFrame.maxY))
    }
}

/// Decides which screen the island appears on and in which form
/// (notch / pill, normal / compact).
@MainActor
enum ScreenLocator {
    /// Test hooks, settable from the command line (see TESTING.md):
    /// `-debugIslandStyle pill`, `-debugCompact YES`, `-debugReduceMotion YES`.
    private static var forcePill: Bool { UserDefaults.standard.string(forKey: "debugIslandStyle") == "pill" }
    private static var forceCompact: Bool { UserDefaults.standard.bool(forKey: "debugCompact") }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || UserDefaults.standard.bool(forKey: "debugReduceMotion")
    }

    /// macOS records where on the global desktop a capture was taken
    /// (`kMDItemScreenCaptureGlobalRect`, top-left origin). `nil` for recordings and
    /// anything not produced by the system screenshot tool.
    static func captureRect(of url: URL) -> CGRect? {
        let name = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, length, 0, 0) }
        guard read == length,
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [NSNumber],
              values.count == 4
        else { return nil }
        return CGRect(
            x: values[0].doubleValue, y: values[1].doubleValue,
            width: values[2].doubleValue, height: values[3].doubleValue)
    }

    /// The screen the capture was taken on; failing that, the one under the pointer;
    /// failing that, the main screen.
    static func screen(forCaptureRect rect: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        if let rect {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let match = screens.first { screen in
                guard let id = screen.displayID else { return false }
                return CGDisplayBounds(id).contains(center)
            }
            if let match { return match }
        }
        if let index = NotchGeometry.screenIndex(
            containing: NSEvent.mouseLocation, frames: screens.map(\.frame)) {
            return screens[index]
        }
        return NSScreen.main ?? screens.first
    }

    static func layout(for screen: NSScreen) -> IslandLayout {
        var description = screen.islandDescription
        if forcePill {
            description.safeAreaTop = 0
            description.auxiliaryTopLeftWidth = nil
            description.auxiliaryTopRightWidth = nil
        }
        let compact = forceCompact || isFullscreenAppActive(on: screen)
        return NotchGeometry.layout(for: description, compact: compact)
    }

    /// Whether an app is in native fullscreen on `screen` right now.
    /// Uses only window bounds/levels from the window list — no Screen Recording permission.
    static func isFullscreenAppActive(on screen: NSScreen) -> Bool {
        guard let id = screen.displayID,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let display = CGDisplayBounds(id)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var appWindows: [CGRect] = []
        var menuBarVisible = false

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { continue }
            let pid = window[kCGWindowOwnerPID as String] as? Int32
            if layer == 0, pid != ownPID {
                appWindows.append(bounds)
            } else if layer == Int(CGWindowLevelForKey(.mainMenuWindow)),
                      display.intersects(bounds), bounds.width >= display.width - 1 {
                menuBarVisible = true
            }
        }
        return NotchGeometry.isFullscreen(
            windowBounds: appWindows,
            displayBounds: display,
            topInset: screen.safeAreaInsets.top,
            menuBarVisible: menuBarVisible)
    }
}
