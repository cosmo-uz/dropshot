import DropshotCore
import SwiftUI

/// First-run setup: what Dropshot does, then the two system changes it asks consent for.
struct OnboardingView: View {
    let settings: AppSettings
    let integration: SystemIntegration
    let onFinish: () -> Void

    @State private var step: Int
    @State private var folder: URL

    init(
        settings: AppSettings, integration: SystemIntegration,
        initialStep: Int = 0, onFinish: @escaping () -> Void
    ) {
        _step = State(initialValue: initialStep)
        self.settings = settings
        self.integration = integration
        self.onFinish = onFinish
        _folder = State(initialValue: settings.rootFolder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: location
                default: thumbnail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 16)
            .accessibilityLabel("Step \(step + 1) of 3")
        }
        .frame(width: 520, height: 460)
    }

    private func advance() {
        if step >= 2 {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
        }
    }

    // MARK: Screens

    private var welcome: some View {
        OnboardingPage(
            title: "Welcome to Dropshot",
            message: "Take a screenshot the way you always do. It is copied to your clipboard, filed by date, and a preview drops out of the notch that you can drag straight into any app.",
            primary: ("Continue", advance)
        ) {
            NotchDemo()
        }
    }

    private var location: some View {
        OnboardingPage(
            title: "Move screenshots off your Desktop?",
            message: "Dropshot will tell macOS to save screenshots here and sort them into dated folders. You can undo this at any time in Settings → About.",
            primary: ("Move Screenshots Here", {
                integration.moveScreenshots(to: folder)
                advance()
            }),
            secondary: ("Not Now", advance)
        ) {
            VStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                HStack(spacing: 8) {
                    Text((folder.path as NSString).abbreviatingWithTildeInPath)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    Button("Choose…") {
                        if let chosen = SystemIntegration.chooseFolder(startingAt: folder) {
                            folder = chosen
                        }
                    }
                }
                Text("e.g. \(PathPlanner(root: folder).subfolderComponents(for: Date()).joined(separator: "/"))/Screenshot….png")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var thumbnail: some View {
        OnboardingPage(
            title: "Turn off macOS's floating thumbnail for instant previews?",
            message: "While macOS shows its own thumbnail in the corner of the screen, it holds the file back for about 5 seconds. With it off, Dropshot copies and previews your screenshot instantly. You can undo this in Settings.",
            primary: ("Turn Off Floating Thumbnail", {
                integration.setThumbnailHidden(true)
                advance()
            }),
            secondary: ("Keep It", advance)
        ) {
            HStack(spacing: 28) {
                DelayBadge(symbol: "rectangle.inset.bottomtrailing.filled", label: "macOS thumbnail", value: "~5 s", tint: .secondary)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                DelayBadge(symbol: "bolt.fill", label: "Dropshot preview", value: "instant", tint: .green)
            }
        }
    }
}

private struct OnboardingPage<Art: View>: View {
    let title: String
    let message: String
    let primary: (String, () -> Void)
    var secondary: (String, () -> Void)?
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 0) {
            art
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .padding(.top, 20)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 44)
            .padding(.top, 8)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Button(action: primary.1) {
                    Text(primary.0).frame(minWidth: 220)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .buttonStyle(.link)
                } else {
                    // Keeps the primary button at the same height on every screen.
                    Text(" ").hidden()
                }
            }
            .padding(.bottom, 18)
        }
    }
}

private struct DelayBadge: View {
    let symbol: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(tint)
                .frame(height: 46)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(width: 140)
    }
}

/// A miniature of the real thing: a notch that springs open with a thumbnail, on a loop.
struct NotchDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fixed state for offscreen rendering (no animation loop).
    var fixedOpen: Bool?
    @State private var open = false

    private let collapsed = CGSize(width: 96, height: 18)
    private let expanded = CGSize(width: 230, height: 92)

    var body: some View {
        let isOpen = fixedOpen ?? open
        let size = isOpen ? expanded : collapsed

        ZStack(alignment: .top) {
            // A slice of a MacBook display.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.accentColor.opacity(0.55), Color.purple.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(height: collapsed.height)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))

            ZStack(alignment: .top) {
                Color.black
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        .frame(width: 84, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Copied ✓")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(red: 0.35, green: 0.9, blue: 0.5))
                        Text("3024 × 1964")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, collapsed.height + 6)
                .frame(width: expanded.width, height: expanded.height, alignment: .top)
                .opacity(isOpen ? 1 : 0)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(IslandShape(style: .notch, topRadius: isOpen ? 6 : 0, bottomRadius: isOpen ? 20 : 7))
            .shadow(color: .black.opacity(isOpen ? 0.3 : 0), radius: 8, y: 5)
        }
        .frame(width: 340, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
        .task {
            guard fixedOpen == nil else { return }
            if reduceMotion {
                open = true
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { open = true }
                try? await Task.sleep(for: .seconds(2.4))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { open = false }
            }
        }
    }
}
