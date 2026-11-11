import Foundation

/// How captures are grouped below the root folder.
public enum FolderPattern: String, CaseIterable, Sendable, Identifiable {
    case yearMonthDay
    case yearMonth
    case flat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yearMonthDay: "YYYY/MM/DD"
        case .yearMonth: "YYYY-MM"
        case .flat: "No subfolders"
        }
    }
}

/// How capture files are named once sorted.
public enum RenamePattern: String, CaseIterable, Sendable, Identifiable {
    /// Keep whatever macOS called it, e.g. "Screenshot 2026-11-11 at 15.41.07.png".
    case original
    /// "2026-11-11_15-41-07.png"
    case compact

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .original: "macOS default"
        case .compact: "YYYY-MM-DD_HH-MM-SS"
        }
    }

    public var example: String {
        switch self {
        case .original: "Screenshot 2026-11-11 at 15.41.07.png"
        case .compact: "2026-11-11_15-41-07.png"
        }
    }
}

/// Pure path math: where a capture taken at `date` should end up.
public struct PathPlanner: Sendable {
    public var root: URL
    public var folderPattern: FolderPattern
    public var renamePattern: RenamePattern
    public var calendar: Calendar

    public init(
        root: URL,
        folderPattern: FolderPattern = .yearMonthDay,
        renamePattern: RenamePattern = .original,
        calendar: Calendar = PathPlanner.defaultCalendar()
    ) {
        self.root = root
        self.folderPattern = folderPattern
        self.renamePattern = renamePattern
        self.calendar = calendar
    }

    /// Gregorian, so folder names are stable regardless of the user's calendar setting.
    public static func defaultCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Path components below the root, e.g. ["2026", "11", "11"].
    public func subfolderComponents(for date: Date) -> [String] {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", parts.year ?? 0)
        let month = String(format: "%02d", parts.month ?? 0)
        let day = String(format: "%02d", parts.day ?? 0)
        switch folderPattern {
        case .yearMonthDay: return [year, month, day]
        case .yearMonth: return ["\(year)-\(month)"]
        case .flat: return []
        }
    }

    public func directory(for date: Date) -> URL {
        subfolderComponents(for: date).reduce(root) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
    }

    /// File name (with extension) for a capture originally called `originalName`.
    public func fileName(originalName: String, date: Date) -> String {
        switch renamePattern {
        case .original:
            return originalName
        case .compact:
            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            let stem = String(
                format: "%04d-%02d-%02d_%02d-%02d-%02d",
                parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
            let ext = (originalName as NSString).pathExtension.lowercased()
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
    }

    /// Final destination. `exists` is consulted so an existing file is never overwritten:
    /// "name.png" → "name 2.png" → "name 3.png" …
    public func destination(
        originalName: String,
        date: Date,
        exists: (URL) -> Bool
    ) -> URL {
        let directory = directory(for: date)
        let name = fileName(originalName: originalName, date: date)
        let candidate = directory.appendingPathComponent(name, isDirectory: false)
        guard exists(candidate) else { return candidate }

        let ns = name as NSString
        let stem = ns.deletingPathExtension
        let ext = ns.pathExtension
        var counter = 2
        while counter < 10_000 {
            let numbered = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            let url = directory.appendingPathComponent(numbered, isDirectory: false)
            if !exists(url) { return url }
            counter += 1
        }
        // Practically unreachable; fall back to something guaranteed unique.
        let unique = ext.isEmpty ? "\(stem) \(UUID().uuidString)" : "\(stem) \(UUID().uuidString).\(ext)"
        return directory.appendingPathComponent(unique, isDirectory: false)
    }
}
