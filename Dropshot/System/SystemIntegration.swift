import AppKit
import Foundation
import Observation

/// UI-facing view of the two macOS screenshot preferences Dropshot manages. Settings and
/// onboarding bind to this; every change goes through `SystemDefaultsService`, which
/// records what was there before so "Restore macOS defaults" can put it back.
@MainActor
@Observable
final class SystemIntegration {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let service: SystemDefaultsService

    /// macOS is saving screenshots into Dropshot's root folder.
    private(set) var savesToRoot = false
    /// macOS's own floating thumbnail is off.
    private(set) var thumbnailHidden = false
    /// Dropshot has changed something that can be reverted.
    private(set) var canRestore = false
    private(set) var systemLocation: URL

    init(settings: AppSettings, service: SystemDefaultsService) {
        self.settings = settings
        self.service = service
        systemLocation = service.currentLocation
        refresh()
    }

    /// Re-reads the system values (the user may have changed them elsewhere).
    func refresh() {
        systemLocation = service.currentLocation
        savesToRoot = service.isLocation(settings.rootFolder)
        thumbnailHidden = !service.isSystemThumbnailEnabled
        canRestore = service.hasAnythingToRestore
    }

    var customNamePrefix: String? { service.customNamePrefix }

    /// One line for the menu bar menu.
    var statusText: String {
        if !settings.onboardingCompleted { return "Setup not finished" }
        if settings.paused { return "Paused" }
        if !savesToRoot { return "macOS is not saving to the Dropshot folder" }
        return "Watching for screenshots"
    }

    // MARK: Screenshot location

    func setSavesToRoot(_ enabled: Bool) {
        if enabled {
            service.applyLocation(settings.rootFolder)
        } else {
            service.restoreLocation()
            // Restoring is a no-op if the location was already ours before Dropshot
            // recorded anything; nothing more to do in that case.
        }
        refresh()
    }

    /// Changes Dropshot's root folder. If macOS was saving into the old root, it follows.
    func changeRootFolder(to folder: URL) {
        let wasSavingToRoot = service.isLocation(settings.rootFolder)
        settings.rootFolderPath = folder.standardizedFileURL.path
        if wasSavingToRoot {
            service.applyLocation(settings.rootFolder)
        }
        refresh()
    }

    /// Onboarding step 2: pick the folder and point macOS at it in one go.
    func moveScreenshots(to folder: URL) {
        settings.rootFolderPath = folder.standardizedFileURL.path
        service.applyLocation(settings.rootFolder)
        refresh()
    }

    // MARK: Floating thumbnail

    func setThumbnailHidden(_ hidden: Bool) {
        if hidden {
            service.disableSystemThumbnail()
        } else {
            service.restoreSystemThumbnail()
            if !service.isSystemThumbnailEnabled {
                service.enableSystemThumbnail()
            }
        }
        refresh()
    }

    // MARK: Restore

    /// Puts every macOS setting back exactly as it was before Dropshot touched it.
    func restoreDefaults() {
        service.restoreAll()
        refresh()
    }

    // MARK: Folder picker

    /// Standard open panel for choosing a screenshots folder. `nil` if cancelled.
    static func chooseFolder(startingAt folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where Dropshot keeps your screenshots"
        var start = folder
        while !FileManager.default.fileExists(atPath: start.path), start.pathComponents.count > 1 {
            start = start.deletingLastPathComponent()
        }
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }
}
