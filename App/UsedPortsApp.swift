import SwiftUI

@main
struct UsedPortsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("UsedPorts", id: "main") {
            PortListView(
                viewModel: appDelegate.host.viewModel,
                privilege: appDelegate.host.privilege,
                toasts: appDelegate.host.toasts,
                settings: appDelegate.host.settings
            )
            .frame(minWidth: 900, minHeight: 500)
        }

        Settings {
            SettingsView(settings: appDelegate.host.settings,
                         viewModel: appDelegate.host.viewModel,
                         updater: appDelegate.host.updater,
                         logStore: appDelegate.host.logStore,
                         notifier: appDelegate.host.portNotifier)
        }
    }
}
