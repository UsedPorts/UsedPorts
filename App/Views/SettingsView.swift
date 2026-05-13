import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("로그인 시 자동 시작", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 180)
        .padding()
        .onAppear { settings.syncFromSystem() }
    }
}
