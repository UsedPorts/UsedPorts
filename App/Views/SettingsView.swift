import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var logStore: LogStore

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
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.autoCheckEnabled)
                HStack {
                    Button("Check Now") {
                        Task { await updater.checkNow() }
                    }
                    .disabled(updater.isChecking)
                    Spacer()
                    if let last = updater.lastCheckDate {
                        Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if updater.isNewAvailable, let v = updater.latestVersion {
                    HStack {
                        Text("New version \(v) is available")
                        Spacer()
                        Button("View Release") { updater.openReleasePage() }
                    }
                }
            }
            Section("Help") {
                Text("If something went wrong, save the diagnostic log and attach it to a GitHub issue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save Diagnostic Log…") {
                        Task { _ = await logStore.saveReport() }
                    }
                    Button("Report Issue on GitHub…") {
                        logStore.openGitHubIssue()
                    }
                }
                Text("Reporting opens a pre-filled GitHub issue and copies the log to your clipboard so you can paste it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 480)
        .padding()
        .onAppear { settings.syncFromSystem() }
    }
}
