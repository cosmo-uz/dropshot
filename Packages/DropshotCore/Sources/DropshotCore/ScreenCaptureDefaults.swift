import Foundation

public enum PreferenceValue: Sendable, Equatable, Codable {
    case string(String)
    case bool(Bool)
}

/// A preferences domain we can read and write (`com.apple.screencapture` in production).
public protocol PreferenceStore: AnyObject {
    func value(forKey key: String) -> PreferenceValue?
    /// Passing `nil` removes the key.
    func setValue(_ value: PreferenceValue?, forKey key: String)
}

/// Where the "what was there before us" record is kept (the app's own defaults in production).
public protocol BackupStorage: AnyObject {
    func loadBackup() -> Data?
    func saveBackup(_ data: Data?)
}

/// Applies Dropshot's changes to the system screenshot preferences and can undo them exactly.
///
/// For each setting we touch, the previous value (or the fact that there was none) is
/// recorded the first time we change it. Restoring puts that back — unless the user has
/// since changed the setting themselves, in which case their choice wins.
public final class ScreenCaptureDefaults {
    public enum Setting: String, CaseIterable, Sendable, Codable {
        case location
        case showThumbnail = "show-thumbnail"
    }

    struct Entry: Codable, Equatable {
        /// `nil` means the key did not exist before we set it.
        var previous: PreferenceValue?
        var applied: PreferenceValue
    }

    private let system: PreferenceStore
    private let backup: BackupStorage
    private var entries: [String: Entry]

    public init(system: PreferenceStore, backup: BackupStorage) {
        self.system = system
        self.backup = backup
        if let data = backup.loadBackup(),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    public func currentValue(of setting: Setting) -> PreferenceValue? {
        system.value(forKey: setting.rawValue)
    }

    /// True while a value we wrote is recorded for `setting` (i.e. there is something to restore).
    public func isManaged(_ setting: Setting) -> Bool {
        entries[setting.rawValue] != nil
    }

    public var hasAnythingToRestore: Bool { !entries.isEmpty }

    /// The value that was in place before Dropshot changed `setting`.
    public func previousValue(of setting: Setting) -> PreferenceValue? {
        entries[setting.rawValue]?.previous
    }

    /// Writes `value`, remembering what was there the first time.
    /// Returns `true` if the system value actually changed.
    @discardableResult
    public func apply(_ value: PreferenceValue, to setting: Setting) -> Bool {
        let key = setting.rawValue
        let current = system.value(forKey: key)
        if var entry = entries[key] {
            // Already managed: keep the original backup, just track the new applied value.
            entry.applied = value
            entries[key] = entry
        } else {
            entries[key] = Entry(previous: current, applied: value)
        }
        persist()
        guard current != value else { return false }
        system.setValue(value, forKey: key)
        return true
    }

    /// Puts back the value that preceded us. Returns `true` if the system value changed.
    @discardableResult
    public func restore(_ setting: Setting) -> Bool {
        let key = setting.rawValue
        guard let entry = entries[key] else { return false }
        entries[key] = nil
        persist()

        let current = system.value(forKey: key)
        // The user changed it after us — leave their choice alone.
        guard current == entry.applied else { return false }
        guard current != entry.previous else { return false }
        system.setValue(entry.previous, forKey: key)
        return true
    }

    /// Restores every setting we manage. Returns the settings whose system value changed.
    @discardableResult
    public func restoreAll() -> [Setting] {
        Setting.allCases.filter { restore($0) }
    }

    private func persist() {
        if entries.isEmpty {
            backup.saveBackup(nil)
        } else {
            backup.saveBackup(try? JSONEncoder().encode(entries))
        }
    }
}
