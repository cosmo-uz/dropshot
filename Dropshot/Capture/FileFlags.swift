import Foundation

/// Extended-attribute helpers.
enum FileFlags {
    /// Set by macOS on everything `screencapture` produces (it backs `kMDItemIsScreenCapture`).
    static let screenCapture = "com.apple.metadata:kMDItemIsScreenCapture"
    /// Set by us once a capture has been handled, so it is never processed twice —
    /// even across relaunches or when the user later edits the file in place.
    static let processed = "app.dropshot.processed"

    static func has(_ name: String, atPath path: String) -> Bool {
        getxattr(path, name, nil, 0, 0, 0) >= 0
    }

    @discardableResult
    static func set(_ name: String, atPath path: String) -> Bool {
        var value: UInt8 = 1
        return setxattr(path, name, &value, 1, 0, 0) == 0
    }

    struct Info {
        var identity: String
        var created: Date
        var modified: Date
    }

    /// Device + inode identity and timestamps; `nil` if the file is gone.
    static func info(atPath path: String) -> Info? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        func date(_ spec: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(spec.tv_sec) + TimeInterval(spec.tv_nsec) / 1e9)
        }
        return Info(
            identity: "\(st.st_dev):\(st.st_ino)",
            created: date(st.st_birthtimespec),
            modified: date(st.st_mtimespec))
    }
}
