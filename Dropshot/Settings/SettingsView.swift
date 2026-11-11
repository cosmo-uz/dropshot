import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Pause Dropshot", isOn: $settings.paused)
            Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 200)
    }
}
