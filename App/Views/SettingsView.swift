import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("로그인 시 자동 시작", isOn: $settings.launchAtLogin)
                Toggle("메뉴바에 표시", isOn: $settings.showMenuBar)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 200)
        .padding()
        .onAppear { settings.syncFromSystem() }
    }
}
