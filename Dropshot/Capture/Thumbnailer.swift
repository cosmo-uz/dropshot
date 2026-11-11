import AVFoundation
import CoreGraphics
import DropshotCore
import Foundation
import ImageIO

/// Small previews and basic facts about a capture, produced off the main thread.
enum Thumbnailer {
    struct Result: Sendable {
        var image: CGImage?
        /// Full pixel dimensions of the capture.
        var pixelSize: CGSize?
        /// Recordings only.
        var duration: TimeInterval?
    }

    /// Never decodes the full-size image: memory stays flat even for 6K captures.
    static func make(for url: URL, kind: CaptureKind, maxPixel: Int = 480) async -> Result {
        switch kind {
        case .image: return image(url, maxPixel: maxPixel)
        case .recording: return await recording(url, maxPixel: maxPixel)
        }
    }

    private static func image(_ url: URL, maxPixel: Int) -> Result {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return Result() }

        var size: CGSize?
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Double,
           let height = properties[kCGImagePropertyPixelHeight] as? Double {
            size = CGSize(width: width, height: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return Result(image: thumbnail, pixelSize: size)
    }

    private static func recording(_ url: URL, maxPixel: Int) async -> Result {
        let asset = AVURLAsset(url: url)
        var result = Result()

        if let duration = try? await asset.load(.duration), duration.isNumeric {
            result.duration = duration.seconds
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            result.pixelSize = CGSize(width: abs(rect.width), height: abs(rect.height))
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        if let frame = try? await generator.image(at: .zero) {
            result.image = frame.image
        }
        return result
    }
}
