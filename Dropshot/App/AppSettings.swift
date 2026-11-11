import DropshotCore
import Foundation
import Observation

extension Notification.Name {
    /// Posted (on the main actor) whenever a persisted setting changes.
    static let dropshotSettingsChanged = Notification.Name("DropshotSettingsChanged")
}

/// User preferences, persisted in the app's own defaults domain.
///
/// Every key can be overridden for a single run from the command line
/// (`-rootFolderPath /tmp/x -onboardingCompleted YES`), which is how TESTING.md
/// exercises the app without touching real settings.
@MainActor
@Observable
final class AppSettings {
    enum Key {
        static let rootFolderPath = "rootFolderPath"
        static let folderPattern = "folderPattern"
        static let renamePattern = "renamePattern"
        static let copyToClipboard = "copyToClipboard"
        static let previewDuration = "previewDuration"
        static let playSound = "playSound"
        static let paused = "paused"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let onboardingCompleted = "onboardingCompleted"
        static let historyEnabled = "historyEnabled"
        static let historyShortcut = "historyShortcut"
        static let pasteDirectly = "pasteDirectly"
    }

    static let previewDurationRange: ClosedRange<Double> = 2...10

    static var defaultRootFolder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("Screenshots", isDirectory: true)
    }

    @ObservationIgnored private let store: UserDefaults

    var rootFolderPath: String { didSet { save(rootFolderPath, Key.rootFolderPath) } }
    var folderPattern: FolderPattern { didSet { save(folderPattern.rawValue, Key.folderPattern) } }
    var renamePattern: RenamePattern { didSet { save(renamePattern.rawValue, Key.renamePattern) } }
    var copyToClipboard: Bool { didSet { save(copyToClipboard, Key.copyToClipboard) } }
    var previewDuration: Double { didSet { save(previewDuration, Key.previewDuration) } }
    var playSound: Bool { didSet { save(playSound, Key.playSound) } }
    var paused: Bool { didSet { save(paused, Key.paused) } }
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, Key.showMenuBarIcon) } }
    var onboardingCompleted: Bool { didSet { save(onboardingCompleted, Key.onboardingCompleted) } }
    var historyEnabled: Bool { didSet { save(historyEnabled, Key.historyEnabled) } }
    var historyShortcut: HistoryShortcut { didSet { save(historyShortcut.rawValue, Key.historyShortcut) } }
    var pasteDirectly: Bool { didSet { save(pasteDirectly, Key.pasteDirectly) } }

    var rootFolder: URL {
        URL(fileURLWithPath: (rootFolderPath as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        store.register(defaults: [
            Key.rootFolderPath: Self.defaultRootFolder.path,
            Key.folderPattern: FolderPattern.yearMonthDay.rawValue,
            Key.renamePattern: RenamePattern.original.rawValue,
            Key.copyToClipboard: true,
            Key.previewDuration: 4.0,
            Key.playSound: false,
            Key.paused: false,
            Key.showMenuBarIcon: true,
            Key.onboardingCompleted: false,
            Key.historyEnabled: true,
            Key.historyShortcut: HistoryShortcut.commandShiftV.rawValue,
            Key.pasteDirectly: false,
        ])
        rootFolderPath = store.string(forKey: Key.rootFolderPath) ?? Self.defaultRootFolder.path
        folderPattern = store.string(forKey: Key.folderPattern).flatMap(FolderPattern.init(rawValue:))
            ?? .yearMonthDay
        renamePattern = store.string(forKey: Key.renamePattern).flatMap(RenamePattern.init(rawValue:))
            ?? .original
        copyToClipboard = store.bool(forKey: Key.copyToClipboard)
        let duration = store.double(forKey: Key.previewDuration)
        previewDuration = min(max(duration, Self.previewDurationRange.lowerBound),
                              Self.previewDurationRange.upperBound)
        playSound = store.bool(forKey: Key.playSound)
        paused = store.bool(forKey: Key.paused)
        showMenuBarIcon = store.bool(forKey: Key.showMenuBarIcon)
        onboardingCompleted = store.bool(forKey: Key.onboardingCompleted)
        historyEnabled = store.bool(forKey: Key.historyEnabled)
        historyShortcut = store.string(forKey: Key.historyShortcut).flatMap(HistoryShortcut.init(rawValue:))
            ?? .commandShiftV
        pasteDirectly = store.bool(forKey: Key.pasteDirectly)
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        NotificationCenter.default.post(name: .dropshotSettingsChanged, object: self)
    }
}
