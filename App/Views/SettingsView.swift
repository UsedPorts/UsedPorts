import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var updater: BrewUpdater
    @ObservedObject var logStore: LogStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Hide repeated process names", isOn: $settings.menuBarGroupSamePid)
                Toggle("Hide duplicate rows", isOn: $settings.hideDuplicateRows)
                Toggle("Group by PID", isOn: $settings.groupByPid)
                Toggle("Show process icons", isOn: $settings.showProcessIcons)
            }
            Section("Menu Bar") {
                Toggle("Show in Menu Bar", isOn: $settings.showMenuBar)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title format")
                    Picker(selection: $settings.menuBarCompact) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Port only")
                            Text("●  3000   ○  3001")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .tag(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Port + process")
                            Text("●  3000 Node.js   ○  3001 nginx")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .tag(false)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .padding(.leading, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!settings.showMenuBar)
            }
            Section("Refresh") {
                Toggle("Auto refresh", isOn: Binding(
                    get: { viewModel.autoRefresh },
                    set: { on in
                        viewModel.autoRefresh = on
                        if on { viewModel.bootstrapIfNeeded(interval: settings.refreshIntervalSeconds) }
                        else { Task { await viewModel.stopStream() } }
                    }
                ))
                Picker("Foreground refresh interval", selection: $settings.refreshIntervalSeconds) {
                    Text("1 second").tag(1.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                .disabled(!viewModel.autoRefresh)
                Picker("Background refresh interval", selection: $settings.backgroundRefreshMode) {
                    Text("Same as foreground").tag(BackgroundRefreshMode.same)
                    Text("Slower (2× interval)").tag(BackgroundRefreshMode.slower)
                    Text("Pause").tag(BackgroundRefreshMode.paused)
                }
                .disabled(!viewModel.autoRefresh)
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
                Group {
                    if let latest = updater.latestVersion {
                        // Side by side when it fits; if the versions are long enough
                        // to overflow, wrap to Current on one line, Latest on the next
                        // instead of truncating.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Text("Current version: \(updater.currentVersion)")
                                Spacer(minLength: 8)
                                Text("Latest version: \(latest)")
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current version: \(updater.currentVersion)")
                                Text("Latest version: \(latest)")
                            }
                        }
                    } else {
                        Text("Current version: \(updater.currentVersion)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if updater.isManagedByBrew {
                    Toggle("Automatically check for updates", isOn: $updater.autoCheckEnabled)
                    HStack {
                        Button("Check Now") { updater.checkNow() }
                            .disabled(!updater.canCheckNow)
                        if updater.updateAvailable, let latest = updater.latestVersion {
                            Button("Update to \(latest)") { updater.installUpdate() }
                                .disabled(updater.isInstalling)
                        }
                        Spacer()
                        if let last = updater.lastCheckDate {
                            Text("Last checked: \(last.formatted(date: .abbreviated, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if updater.updateAvailable {
                        Text("A new version is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if updater.lastCheckFailed {
                        Text("Last update check failed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("UsedPorts is not managed by Homebrew. Install via Homebrew to enable in-app updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Homebrew Install Instructions…") { updater.openReleasesPage() }
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
