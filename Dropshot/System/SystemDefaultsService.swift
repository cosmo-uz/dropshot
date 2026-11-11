import DropshotCore
import Foundation

/// `PreferenceStore` backed by CFPreferences for an arbitrary domain.
final class CFPreferenceStore: PreferenceStore {
    let domain: String

    init(domain: String) {
        self.domain = domain
    }

    func value(forKey key: String) -> PreferenceValue? {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return nil }
        if CFGetTypeID(raw) == CFBooleanGetTypeID(), let bool = raw as? Bool { return .bool(bool) }
        if let string = raw as? String { return .string(string) }
        if let number = raw as? NSNumber { return .bool(number.boolValue) }
        return nil
    }

    func setValue(_ value: PreferenceValue?, forKey key: String) {
        let cfValue: CFPropertyList?
        switch value {
        case .string(let string): cfValue = string as CFString
        case .bool(let bool): cfValue = bool ? kCFBooleanTrue : kCFBooleanFalse
        case nil: cfValue = nil
        }
        CFPreferencesSetAppValue(key as CFString, cfValue, domain as CFString)
        if !CFPreferencesAppSynchronize(domain as CFString) {
            Log.system.error("Could not synchronise \(self.domain, privacy: .public)")
        }
    }

    func string(forKey key: String) -> String? {
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
    }
}

final class UserDefaultsBackup: BackupStorage {
    private let store: UserDefaults
    private let key: String

    init(store: UserDefaults = .standard, key: String = "systemDefaultsBackup") {
        self.store = store
        self.key = key
    }

    func loadBackup() -> Data? { store.data(forKey: key) }

    func saveBackup(_ data: Data?) {
        if let data { store.set(data, forKey: key) } else { store.removeObject(forKey: key) }
    }
}

/// Everything Dropshot changes outside its own sandbox of preferences lives here:
/// the screenshot save location and the floating-thumbnail switch.
@MainActor
final class SystemDefaultsService {
    static let systemDomain = "com.apple.screencapture"

    private let store: CFPreferenceStore
    private let defaults: ScreenCaptureDefaults
    private var isRealSystemDomain: Bool { store.domain == Self.systemDomain }

    /// - Parameter domain: overridable (`-screencaptureDomain some.test.domain`) so the
    ///   apply/restore path can be exercised end to end without touching real settings.
    init(domain: String? = nil) {
        let domain = domain
            ?? UserDefaults.standard.string(forKey: "screencaptureDomain")
            ?? Self.systemDomain
        store = CFPreferenceStore(domain: domain)
        // A test domain keeps its own backup record so it can never disturb the real one.
        let backupKey = domain == Self.systemDomain ? "systemDefaultsBackup" : "systemDefaultsBackup.\(domain)"
        defaults = ScreenCaptureDefaults(system: store, backup: UserDefaultsBackup(key: backupKey))
        if domain != Self.systemDomain {
            Log.system.notice("Using test preferences domain \(domain, privacy: .public)")
        }
    }

    // MARK: Reading

    /// Where macOS currently saves screenshots (Desktop when unset).
    var currentLocation: URL {
        CFPreferencesAppSynchronize(store.domain as CFString)
        if case .string(let path) = defaults.currentValue(of: .location), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Whether macOS shows its own floating thumbnail (on when unset).
    var isSystemThumbnailEnabled: Bool {
        CFPreferencesAppSynchronize(store.domain as CFString)
        if case .bool(let enabled) = defaults.currentValue(of: .showThumbnail) { return enabled }
        return true
    }

    func isLocation(_ folder: URL) -> Bool {
        currentLocation.path == folder.standardizedFileURL.path
    }

    var domain: String { store.domain }
    var customNamePrefix: String? { store.string(forKey: "name") }
    var hasAnythingToRestore: Bool { defaults.hasAnythingToRestore }
    var isLocationManaged: Bool { defaults.isManaged(.location) }
    var isThumbnailManaged: Bool { defaults.isManaged(.showThumbnail) }

    // MARK: Writing

    func applyLocation(_ folder: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.system.error("Cannot create \(folder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        if defaults.apply(.string(folder.standardizedFileURL.path), to: .location) {
            Log.system.info("Screenshot location → \(folder.path, privacy: .public)")
            reloadSystemUI()
        }
    }

    func restoreLocation() {
        if defaults.restore(.location) {
            Log.system.info("Screenshot location restored")
            reloadSystemUI()
        }
    }

    func disableSystemThumbnail() {
        if defaults.apply(.bool(false), to: .showThumbnail) {
            Log.system.info("Floating thumbnail disabled")
            reloadSystemUI()
        }
    }

    func restoreSystemThumbnail() {
        if defaults.restore(.showThumbnail) {
            Log.system.info("Floating thumbnail setting restored")
            reloadSystemUI()
        }
    }

    /// For someone who had already switched the thumbnail off before installing Dropshot
    /// and now wants it back: restoring would be a no-op, so write `true` (still undoable).
    func enableSystemThumbnail() {
        if defaults.apply(.bool(true), to: .showThumbnail) {
            Log.system.info("Floating thumbnail enabled")
            reloadSystemUI()
        }
    }

    /// Undoes every system change Dropshot made. Returns `true` if anything changed.
    @discardableResult
    func restoreAll() -> Bool {
        let changed = defaults.restoreAll()
        guard !changed.isEmpty else { return false }
        Log.system.info("Restored macOS defaults: \(changed.map(\.rawValue).joined(separator: ", "), privacy: .public)")
        reloadSystemUI()
        return true
    }

    /// SystemUIServer caches screenshot preferences; restarting it (it relaunches itself
    /// instantly) makes the change take effect without logging out.
    private func reloadSystemUI() {
        guard isRealSystemDomain else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["SystemUIServer"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.system.error("killall SystemUIServer failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
