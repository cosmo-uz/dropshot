import DropshotCore
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let integration: SystemIntegration
    let updater: Updater

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScreenshotSettings(settings: settings, integration: integration)
                .tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            AboutSettings(integration: integration, updater: updater)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 520)
        .onAppear { integration.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            integration.refresh()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at login")
                Toggle("Pause Dropshot", isOn: $settings.paused)
            } footer: {
                Caption("While paused, screenshots stay where macOS puts them: nothing is copied, moved or previewed.")
            }
            Section {
                Toggle("Clipboard history", isOn: $settings.historyEnabled)
                Picker("Shortcut", selection: $settings.historyShortcut) {
                    ForEach(HistoryShortcut.allCases) { Text($0.displayName).tag($0) }
                }
                .disabled(!settings.historyEnabled)
                Toggle("Paste the chosen item directly", isOn: Binding(
                    get: { settings.pasteDirectly },
                    set: { enabled in
                        settings.pasteDirectly = enabled
                        if enabled { HistoryPanelController.requestPastePermission() }
                    }))
                    .disabled(!settings.historyEnabled)
            } footer: {
                Caption("Press the shortcut anywhere to see the last \(ClipboardHistory.maxItems) things you copied. History is kept in memory only and is forgotten when Dropshot quits; passwords from password managers are skipped. Pasting directly needs the Accessibility permission; without it the item is copied and you press ⌘V.")
            }
            Section {
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            } footer: {
                Caption("With the icon hidden, open Dropshot again from Finder or Spotlight to get back to these settings.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Screenshots

struct ScreenshotSettings: View {
    @Bindable var settings: AppSettings
    let integration: SystemIntegration

    private var example: String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let planner = PathPlanner(
            root: settings.rootFolder,
            folderPattern: settings.folderPattern,
            renamePattern: settings.renamePattern)
        let name = planner.fileName(
            originalName: "Screenshot \(formatter.string(from: now)).png", date: now)
        return (planner.subfolderComponents(for: now) + [name]).joined(separator: "/")
    }

    var body: some View {
        Form {
            Section("Where screenshots go") {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text((settings.rootFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(settings.rootFolder.path)
                        Button("Choose…") {
                            if let folder = SystemIntegration.chooseFolder(startingAt: settings.rootFolder) {
                                integration.changeRootFolder(to: folder)
                            }
                        }
                    }
                }
                Toggle("Save macOS screenshots to this folder", isOn: Binding(
                    get: { integration.savesToRoot },
                    set: { integration.setSavesToRoot($0) }))
                if !integration.savesToRoot {
                    Label {
                        Text("macOS currently saves screenshots to \((integration.systemLocation.path as NSString).abbreviatingWithTildeInPath), so Dropshot will not see them. Turn this on to fix it.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }
                Picker("Subfolders", selection: $settings.folderPattern) {
                    ForEach(FolderPattern.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("File names", selection: $settings.renamePattern) {
                    ForEach(RenamePattern.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Example") {
                    Text(example)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Section("After a capture") {
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
                LabeledContent("Show preview for") {
                    HStack {
                        Slider(
                            value: $settings.previewDuration,
                            in: AppSettings.previewDurationRange, step: 1)
                            .frame(width: 180)
                        Text("\(Int(settings.previewDuration)) s")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Toggle("Play sound", isOn: $settings.playSound)
            }

            Section {
                Toggle("Hide the macOS floating thumbnail", isOn: Binding(
                    get: { integration.thumbnailHidden },
                    set: { integration.setThumbnailHidden($0) }))
            } footer: {
                Caption("While macOS shows its own thumbnail in the corner it holds the file back for about 5 seconds. Hiding it lets Dropshot copy and preview the screenshot instantly.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettings: View {
    let integration: SystemIntegration
    let updater: Updater
    @State private var confirmingRestore = false
    @State private var didRestore = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dropshot").font(.title2.weight(.semibold))
                        Text(version).foregroundStyle(.secondary)
                        Text("Screenshots off your Desktop, onto your clipboard.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Updates") {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.isConfigured)
                }
            } footer: {
                Caption(updater.isConfigured
                    ? "Updates are the only reason Dropshot ever uses the network."
                    : "This build has no update feed configured, so it never uses the network.")
            }

            Section {
                LabeledContent("macOS settings") {
                    Button("Restore macOS Defaults…") { confirmingRestore = true }
                        .disabled(!integration.canRestore)
                }
            } footer: {
                Caption(restoreCaption)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Restore macOS screenshot settings?", isPresented: $confirmingRestore
        ) {
            Button("Restore") {
                integration.restoreDefaults()
                didRestore = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The screenshot save location and the floating thumbnail go back to exactly what they were before Dropshot changed them. Your existing screenshots are not moved.")
        }
    }

    private var restoreCaption: String {
        if integration.canRestore {
            return "Puts the screenshot save location and the floating thumbnail back exactly as they were before Dropshot changed them."
        }
        return didRestore
            ? "Restored. macOS screenshot settings are as they were before Dropshot."
            : "Dropshot has not changed any macOS settings."
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
