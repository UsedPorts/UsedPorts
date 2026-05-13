import SwiftUI

@main
struct UsedPortsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("UsedPorts", id: "main") {
            PortListView(
                viewModel: appDelegate.host.viewModel,
                privilege: appDelegate.host.privilege,
                toasts: appDelegate.host.toasts
            )
            .frame(minWidth: 900, minHeight: 500)
        }

        Settings {
            SettingsView(settings: appDelegate.host.settings)
        }
    }
}
