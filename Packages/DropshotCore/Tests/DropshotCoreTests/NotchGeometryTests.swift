import XCTest
@testable import DropshotCore

final class NotchGeometryTests: XCTestCase {
    /// 14" MacBook Pro at default scaling: 1512×982, notch 185×32.
    private let notched = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 663.5,
        auxiliaryTopRightWidth: 663.5,
        menuBarHeight: 32)

    /// External 1440p display to the right of the built-in one.
    private let external = ScreenDescription(
        frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
        menuBarHeight: 24)

    // MARK: Notch detection

    func testNotchRectIsCentredAtTheTop() throws {
        let notch = try XCTUnwrap(NotchGeometry.notchRect(for: notched))
        XCTAssertEqual(notch, CGRect(x: 663.5, y: 950, width: 185, height: 32))
        XCTAssertEqual(notch.midX, notched.frame.midX)
        XCTAssertEqual(notch.maxY, notched.frame.maxY)
    }

    func testNoNotchWithoutSafeArea() {
        XCTAssertNil(NotchGeometry.notchRect(for: external))
    }

    func testNoNotchWithoutAuxiliaryAreas() {
        var screen = notched
        screen.auxiliaryTopLeftWidth = nil
        XCTAssertNil(NotchGeometry.notchRect(for: screen))
    }

    func testDegenerateAuxiliaryAreasAreRejected() {
        var screen = notched
        screen.auxiliaryTopLeftWidth = 800
        screen.auxiliaryTopRightWidth = 800
        XCTAssertNil(NotchGeometry.notchRect(for: screen))
    }

    func testNotchRectRespectsScreenOrigin() throws {
        var screen = notched
        screen.frame.origin = CGPoint(x: -1512, y: 300)
        let notch = try XCTUnwrap(NotchGeometry.notchRect(for: screen))
        XCTAssertEqual(notch.minX, -1512 + 663.5)
        XCTAssertEqual(notch.maxY, 300 + 982)
    }

    // MARK: Notch layout

    func testCollapsedIslandMatchesHardwareNotchExactly() {
        let layout = NotchGeometry.layout(for: notched)
        XCTAssertEqual(layout.style, .notch)
        XCTAssertEqual(layout.collapsedSize, CGSize(width: 185, height: 32))
        XCTAssertEqual(layout.topInset, 32)
    }

    func testExpandedIslandGrowsDownAndWider() {
        let layout = NotchGeometry.layout(for: notched)
        XCTAssertGreaterThan(layout.expandedSize.width, layout.collapsedSize.width)
        XCTAssertGreaterThan(layout.expandedSize.height, layout.collapsedSize.height)
        XCTAssertEqual(layout.expandedSize, CGSize(width: 360, height: 132))
    }

    func testWindowIsPinnedToScreenTopAndCentredOnNotch() {
        let layout = NotchGeometry.layout(for: notched)
        XCTAssertEqual(layout.windowFrame.maxY, notched.frame.maxY)
        XCTAssertEqual(layout.windowFrame.midX, notched.frame.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(layout.windowFrame.width, layout.expandedSize.width)
        XCTAssertGreaterThanOrEqual(layout.windowFrame.height, layout.expandedSize.height)
    }

    func testVeryWideNotchStillGetsOverhang() {
        var screen = notched
        screen.auxiliaryTopLeftWidth = 556
        screen.auxiliaryTopRightWidth = 556 // notch = 400
        let layout = NotchGeometry.layout(for: screen)
        XCTAssertEqual(layout.expandedSize.width, 400 + 2 * NotchGeometry.minimumNotchOverhang)
    }

    // MARK: Pill layout

    func testExternalDisplayGetsPillBelowMenuBar() {
        let layout = NotchGeometry.layout(for: external)
        XCTAssertEqual(layout.style, .pill)
        XCTAssertEqual(layout.topInset, 0)
        XCTAssertEqual(layout.collapsedSize, NotchGeometry.pillCollapsedSize)
        XCTAssertEqual(layout.expandedSize, NotchGeometry.expandedContentSize)
        XCTAssertEqual(layout.windowFrame.maxY,
                       external.frame.maxY - 24 - NotchGeometry.pillTopMargin)
        XCTAssertEqual(layout.windowFrame.midX, external.frame.midX, accuracy: 0.5)
    }

    func testPillHugsTopWhenMenuBarIsHidden() {
        var screen = external
        screen.menuBarHeight = 0
        let layout = NotchGeometry.layout(for: screen)
        XCTAssertEqual(layout.windowFrame.maxY, screen.frame.maxY - NotchGeometry.pillTopMargin)
    }

    func testWindowStaysInsideItsScreen() {
        for screen in [notched, external] {
            for compact in [false, true] {
                let layout = NotchGeometry.layout(for: screen, compact: compact)
                XCTAssertTrue(screen.frame.contains(layout.windowFrame),
                              "\(layout.windowFrame) not inside \(screen.frame)")
            }
        }
    }

    func testNarrowScreenClampsWidth() {
        let tiny = ScreenDescription(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let layout = NotchGeometry.layout(for: tiny)
        XCTAssertLessThanOrEqual(layout.expandedSize.width, 320 - 2 * NotchGeometry.windowSideMargin)
        XCTAssertTrue(tiny.frame.contains(layout.windowFrame))
    }

    // MARK: Fullscreen (compact)

    func testCompactLayoutIsSmaller() {
        for screen in [notched, external] {
            let normal = NotchGeometry.layout(for: screen)
            let compact = NotchGeometry.layout(for: screen, compact: true)
            XCTAssertEqual(compact.scale, NotchGeometry.compactScale)
            XCTAssertLessThan(compact.expandedSize.width, normal.expandedSize.width)
            XCTAssertLessThan(compact.expandedSize.height, normal.expandedSize.height)
            XCTAssertEqual(compact.collapsedSize, normal.collapsedSize)
            XCTAssertEqual(compact.style, normal.style)
        }
    }

    func testCompactNotchIslandStillCoversTheNotch() {
        let compact = NotchGeometry.layout(for: notched, compact: true)
        XCTAssertGreaterThanOrEqual(compact.expandedSize.width, compact.collapsedSize.width + 2 * 30)
    }

    func testFullscreenDetection() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // Ordinary windows.
        XCTAssertFalse(NotchGeometry.isFullscreen(
            windowBounds: [CGRect(x: 100, y: 80, width: 900, height: 700)], displayBounds: display))
        // A maximised (zoomed) window still leaves the menu bar.
        XCTAssertFalse(NotchGeometry.isFullscreen(
            windowBounds: [CGRect(x: 0, y: 32, width: 1512, height: 900)], displayBounds: display))
        // True fullscreen.
        XCTAssertTrue(NotchGeometry.isFullscreen(windowBounds: [display], displayBounds: display))
        // Fullscreen below the notch on a notched display.
        let belowNotch = CGRect(x: 0, y: 32, width: 1512, height: 950)
        XCTAssertFalse(NotchGeometry.isFullscreen(windowBounds: [belowNotch], displayBounds: display))
        XCTAssertTrue(NotchGeometry.isFullscreen(
            windowBounds: [belowNotch], displayBounds: display, topInset: 32))
        // …but the same bounds with the menu bar showing is just a zoomed window.
        XCTAssertFalse(NotchGeometry.isFullscreen(
            windowBounds: [belowNotch], displayBounds: display, topInset: 32, menuBarVisible: true))
        // A window covering everything is fullscreen whatever the menu bar says.
        XCTAssertTrue(NotchGeometry.isFullscreen(
            windowBounds: [display], displayBounds: display, topInset: 32, menuBarVisible: true))
        // A fullscreen window on another display does not count.
        XCTAssertFalse(NotchGeometry.isFullscreen(
            windowBounds: [CGRect(x: 1512, y: 0, width: 2560, height: 1440)], displayBounds: display))
        XCTAssertFalse(NotchGeometry.isFullscreen(windowBounds: [], displayBounds: display))
    }

    // MARK: Screen selection

    func testScreenContainingPoint() {
        let frames = [notched.frame, external.frame]
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: 700, y: 500), frames: frames), 0)
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: 3000, y: 100), frames: frames), 1)
        XCTAssertNil(NotchGeometry.screenIndex(containing: CGPoint(x: -500, y: 5000), frames: frames))
    }
}
