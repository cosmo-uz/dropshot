import Foundation

public enum CaptureKind: String, Sendable, Equatable {
    case image
    case recording
}

/// Decides which files in the watched folder are screen captures worth processing.
public enum CaptureClassifier {
    /// Every format `com.apple.screencapture type` can produce.
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "pdf",
    ]
    public static let recordingExtensions: Set<String> = ["mov", "mp4"]

    /// Name prefixes macOS uses for captures (English; other locales rely on the
    /// `kMDItemIsScreenCapture` flag instead, which macOS sets regardless of language).
    public static let knownNamePrefixes = ["Screenshot", "Screen Shot", "Screen Recording"]

    /// How recently a file must have been written to count as "just captured".
    public static let recencyWindow: TimeInterval = 120

    /// In-progress or hidden files: `.Screenshot….png-AbCd`, `foo.tmp`, AppKit safe-save dirs.
    public static func isTemporary(fileName: String) -> Bool {
        if fileName.isEmpty || fileName.hasPrefix(".") { return true }
        let lower = fileName.lowercased()
        if lower.hasSuffix(".tmp") || lower.hasSuffix(".download") || lower.hasSuffix(".part") {
            return true
        }
        return lower.contains(".sb-")
    }

    public static func kind(forFileName fileName: String) -> CaptureKind? {
        guard !isTemporary(fileName: fileName) else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if recordingExtensions.contains(ext) { return .recording }
        return nil
    }

    /// True when `url` sits directly inside `root` (not in a dated subfolder).
    public static func isDirectChild(_ url: URL, of root: URL) -> Bool {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        let rootPath = root.standardizedFileURL.path
        return normalized(parent) == normalized(rootPath)
    }

    private static func normalized(_ path: String) -> String {
        var path = path
        // /private/var and /var (etc.) are the same place; FSEvents reports the former.
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    public static func hasKnownPrefix(fileName: String, customPrefix: String? = nil) -> Bool {
        var prefixes = knownNamePrefixes
        if let customPrefix, !customPrefix.isEmpty { prefixes.append(customPrefix) }
        return prefixes.contains { fileName.hasPrefix($0) }
    }

    /// The final gate before a file is treated as a capture.
    ///
    /// - A file macOS itself flagged as a screen capture always qualifies.
    /// - Otherwise it must look like one by name *and* have been written just now,
    ///   and only while we are reacting to live events (never during a catch-up sweep).
    public static func isCapture(
        fileName: String,
        hasScreenCaptureFlag: Bool,
        lastWritten: Date?,
        now: Date,
        live: Bool,
        customPrefix: String? = nil
    ) -> Bool {
        guard kind(forFileName: fileName) != nil else { return false }
        if hasScreenCaptureFlag { return true }
        guard live, let lastWritten else { return false }
        let age = now.timeIntervalSince(lastWritten)
        guard age >= -5, age <= recencyWindow else { return false }
        return hasKnownPrefix(fileName: fileName, customPrefix: customPrefix)
    }
}
