#if DEBUG
import AppKit
import SwiftUI

/// Debug-only command-line entry points used by TESTING.md. None of them exist in Release.
///
/// - `--defaults-test apply <folder>` / `--defaults-test restore` / `--defaults-test status`
///   drive the real apply/restore code against a *test* preferences domain
///   (`-screencaptureDomain <domain>` is mandatory; the real domain is refused).
/// - `--render-windows <outDir>` renders Settings and onboarding to PNG files offscreen.
@MainActor
enum DebugHooks {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--defaults-test") {
            runDefaultsTest(Array(arguments[(flag + 1)...]))
        }
        if let flag = arguments.firstIndex(of: "--render-windows"), arguments.count > flag + 1 {
            renderWindows(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
        }
    }

    private static func scratchSettings() -> AppSettings {
        let suite = "app.dropshot.debughooks"
        let store = UserDefaults(suiteName: suite) ?? .standard
        return AppSettings(store: store)
    }

    private static func runDefaultsTest(_ arguments: [String]) -> Never {
        let service = SystemDefaultsService()
        guard service.domain != SystemDefaultsService.systemDomain else {
            print("refusing to run against \(SystemDefaultsService.systemDomain); pass -screencaptureDomain <test domain>")
            exit(2)
        }
        let settings = scratchSettings()
        let integration = SystemIntegration(settings: settings, service: service)

        switch arguments.first {
        case "apply":
            guard arguments.count > 1 else { exit(2) }
            integration.moveScreenshots(to: URL(fileURLWithPath: arguments[1], isDirectory: true))
            integration.setThumbnailHidden(true)
        case "restore":
            integration.restoreDefaults()
        case "status":
            break
        default:
            exit(2)
        }
        print("savesToRoot=\(integration.savesToRoot) thumbnailHidden=\(integration.thumbnailHidden) canRestore=\(integration.canRestore) location=\(integration.systemLocation.path)")
        exit(0)
    }

    private static func renderWindows(to outDir: URL) -> Never {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let settings = scratchSettings()
        let service = SystemDefaultsService(domain: "app.dropshot.rendertest")
        let integration = SystemIntegration(settings: settings, service: service)
        let updater = Updater()

        let size = CGSize(width: 500, height: 480)
        let views: [(String, CGSize, AnyView)] = [
            ("settings-1-general", size, AnyView(GeneralSettings(settings: settings))),
            ("settings-2-screenshots", CGSize(width: 500, height: 560),
             AnyView(ScreenshotSettings(settings: settings, integration: integration))),
            ("settings-3-about", size, AnyView(AboutSettings(integration: integration, updater: updater))),
            ("onboarding-1", CGSize(width: 520, height: 460),
             AnyView(OnboardingView(settings: settings, integration: integration, initialStep: 0) {})),
            ("onboarding-2", CGSize(width: 520, height: 460),
             AnyView(OnboardingView(settings: settings, integration: integration, initialStep: 1) {})),
            ("onboarding-3", CGSize(width: 520, height: 460),
             AnyView(OnboardingView(settings: settings, integration: integration, initialStep: 2) {})),
            ("onboarding-demo-open", CGSize(width: 380, height: 200),
             AnyView(NotchDemo(fixedOpen: true).padding(15))),
        ]

        for (name, size, view) in views {
            let hosting = NSHostingView(rootView: view
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            window.layoutIfNeeded()
            // Let SwiftUI settle (forms lay out lazily).
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                print("failed: \(name)")
                continue
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: outDir.appendingPathComponent("\(name).png"))
                print("rendered \(name)")
            }
        }
        exit(0)
    }
}
#endif
