import Foundation

/// Cheap "was this image written to the end?" check based on the format's trailer.
///
/// A file's size can pause mid-write (slow network volume, a busy writer), so a stable
/// size alone is not proof. PNG and JPEG — the formats screenshots are actually saved
/// in — both end with a fixed marker.
public enum ImageCompleteness {
    public static let pngTrailer = Data([0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    public static let jpegTrailer = Data([0xFF, 0xD9])
    /// How many bytes from the end of the file `isComplete` wants to see.
    public static let tailLength = 64

    /// - Returns: `true`/`false` when the format has a known trailer, `nil` when it does not
    ///   (callers fall back to a decoder-based check).
    public static func isComplete(fileExtension: String, tail: Data) -> Bool? {
        switch fileExtension.lowercased() {
        case "png":
            return tail.suffix(pngTrailer.count) == pngTrailer
        case "jpg", "jpeg":
            // Some encoders pad after the end-of-image marker; allow a little slack.
            let trimmed = tail.reversed().drop { $0 == 0x00 }
            return Data(trimmed.prefix(2).reversed()) == jpegTrailer
        default:
            return nil
        }
    }

    /// Reads the last `tailLength` bytes of the file at `path`.
    public static func tail(ofFileAtPath path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let length = min(UInt64(tailLength), size)
        guard (try? handle.seek(toOffset: size - length)) != nil else { return nil }
        return try? handle.readToEnd()
    }
}
