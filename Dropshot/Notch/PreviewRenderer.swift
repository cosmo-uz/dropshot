#if DEBUG
import AppKit
import DropshotCore
import SwiftUI

/// Debug-only: `Dropshot --render-previews <outDir> <image> [<image> …]`
/// renders the island in every state to PNG files, offscreen, and exits.
/// Used to review the design without a live screen (CI, locked session) and for docs.
@MainActor
enum PreviewRenderer {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-previews"), arguments.count > flag + 2 else { return }
        let outDir = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let images = arguments[(flag + 2)...].map { URL(fileURLWithPath: $0) }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let items: [PreviewItem] = images.enumerated().map { index, url in
            let source = NSImage(contentsOf: url)
            let rep = source?.representations.first
            let isMovie = url.pathExtension.lowercased() == "mov"
            return PreviewItem(
                id: UUID(), url: url, kind: isMovie ? .recording : .image,
                thumbnail: source,
                pixelSize: rep.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) },
                duration: isMovie ? 12 : nil,
                copied: true)
        }
        guard let first = items.first else { exit(2) }

        // The real main screen if it has a notch, otherwise a 14" MacBook Pro.
        let real = NSScreen.main?.islandDescription
        let notched = real.flatMap { NotchGeometry.notchRect(for: $0) != nil ? $0 : nil }
            ?? ScreenDescription(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                auxiliaryTopLeftWidth: 663.5, auxiliaryTopRightWidth: 663.5, menuBarHeight: 32)
        let external = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), menuBarHeight: 24)

        struct Case {
            var name: String
            var screen: ScreenDescription
            var compact = false
            var expanded = true
            var hovering = false
            var reduceMotion = false
            var items: [PreviewItem]
        }
        let recording = PreviewItem(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/Screen Recording 2026-11-11 at 15.41.07.mov"),
            kind: .recording, thumbnail: first.thumbnail, pixelSize: CGSize(width: 3024, height: 1964),
            duration: 12, copied: true)

        let cases: [Case] = [
            Case(name: "notch-1-collapsed", screen: notched, expanded: false, items: [first]),
            Case(name: "notch-2-expanded", screen: notched, items: [first]),
            Case(name: "notch-3-hover", screen: notched, hovering: true, items: [first]),
            Case(name: "notch-4-stack", screen: notched, items: Array(items.prefix(3))),
            Case(name: "notch-5-fullscreen-compact", screen: notched, compact: true, items: [first]),
            Case(name: "notch-6-recording", screen: notched, items: [recording]),
            Case(name: "pill-1-collapsed", screen: external, expanded: false, items: [first]),
            Case(name: "pill-2-expanded", screen: external, items: [first]),
            Case(name: "pill-3-hover-stack", screen: external, hovering: true, items: Array(items.prefix(3))),
            Case(name: "pill-4-fullscreen-compact", screen: external, compact: true, items: [first]),
            Case(name: "reduce-motion-hidden", screen: notched, expanded: false, reduceMotion: true, items: [first]),
        ]

        for testCase in cases {
            let layout = NotchGeometry.layout(for: testCase.screen, compact: testCase.compact)
            let model = NotchViewModel(layout: layout)
            model.isStatic = true
            model.items = testCase.items
            model.isExpanded = testCase.expanded
            model.isHovering = testCase.hovering
            model.reduceMotion = testCase.reduceMotion

            let isNotch = layout.style == .notch
            let view = ZStack(alignment: .top) {
                // Stand-in desktop + menu bar so the island's silhouette is visible.
                LinearGradient(colors: [Color(white: 0.78), Color(white: 0.62)], startPoint: .top, endPoint: .bottom)
                if isNotch {
                    Color(white: 0.9).frame(height: layout.topInset)
                }
                NotchRootView(model: model)
            }
            .frame(width: layout.windowFrame.width, height: layout.windowFrame.height)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write(Data("failed: \(testCase.name)\n".utf8))
                continue
            }
            try? data.write(to: outDir.appendingPathComponent("\(testCase.name).png"))
            print("\(testCase.name): island \(layout.collapsedSize) → \(layout.expandedSize), window \(layout.windowFrame)")
        }
        exit(0)
    }
}
#endif
