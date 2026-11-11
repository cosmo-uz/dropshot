import AppKit
import DropshotCore
import ImageIO
import UniformTypeIdentifiers

/// Puts a capture on the general pasteboard.
///
/// Images go on as image data *and* as a file URL, so ⌘V works in image fields
/// (chat apps, editors) and in Finder alike. Recordings go on as a file URL only.
@MainActor
enum ClipboardWriter {
    // The pasteboard does not retain lazy data providers strongly enough to rely on.
    private static var currentProvider: LazyImageProvider?

    @discardableResult
    static func write(_ capture: ProcessedCapture, to pasteboard: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        var provider: LazyImageProvider?

        if capture.kind == .image {
            let nativeType = UTType(filenameExtension: capture.url.pathExtension) ?? .png
            var lazyTypes: [NSPasteboard.PasteboardType] = [.tiff]

            // PNG is what virtually every paste target asks for. Captures are PNG by default,
            // so this is just the file's bytes — no re-encoding on the hot path.
            if nativeType == .png, let data = try? Data(contentsOf: capture.url, options: .mappedIfSafe) {
                item.setData(data, forType: .png)
            } else {
                lazyTypes.insert(.png, at: 0)
                if nativeType != .tiff, nativeType != .pdf,
                   let data = try? Data(contentsOf: capture.url, options: .mappedIfSafe) {
                    item.setData(data, forType: NSPasteboard.PasteboardType(nativeType.identifier))
                }
            }

            // TIFF (and PNG for non-PNG captures) is rendered only if an app asks for it.
            let lazy = LazyImageProvider(url: capture.url)
            item.setDataProvider(lazy, forTypes: lazyTypes)
            provider = lazy
        }

        item.setString(capture.url.absoluteString, forType: .fileURL)

        pasteboard.clearContents()
        let ok = pasteboard.writeObjects([item])
        currentProvider = provider
        if !ok {
            Log.capture.error("Pasteboard refused \(capture.url.lastPathComponent, privacy: .public)")
        }
        return ok
    }
}

/// Converts the capture to the requested image type on demand.
final class LazyImageProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        let target: UTType = type == .png ? .png : .tiff
        guard let data = Self.convert(url, to: target) else { return }
        item.setData(data, forType: type)
    }

    static func convert(_ url: URL, to type: UTType) -> Data? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation else { return nil }
            if type == .tiff { return tiff }
            return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
