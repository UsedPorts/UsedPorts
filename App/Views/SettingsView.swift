import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Show in Menu Bar", isOn: $settings.showMenuBar)
            }
            Section("Language") {
                Picker("Language", selection: $settings.appLanguage) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
                Text("Restart the app to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 280)
        .padding()
        .onAppear { settings.syncFromSystem() }
    }
}
