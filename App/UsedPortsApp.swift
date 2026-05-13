import SwiftUI

@main
struct UsedPortsApp: App {
    private let scanner: PortScanner
    @StateObject private var vm: PortListViewModel
    @StateObject private var priv: PrivilegeManager
    @StateObject private var toasts: ToastCenter
    @StateObject private var settings: AppSettings

    init() {
        let s = PortScanner()
        let t = ToastCenter()
        self.scanner = s
        _toasts = StateObject(wrappedValue: t)
        _vm = StateObject(wrappedValue: PortListViewModel(scanner: s, toasts: t))
        _priv = StateObject(wrappedValue: PrivilegeManager(scanner: s, toasts: t))
        _settings = StateObject(wrappedValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup("UsedPorts", id: "main") {
            PortListView(viewModel: vm, privilege: priv, toasts: toasts)
                .frame(minWidth: 900, minHeight: 500)
        }

        MenuBarExtra("UsedPorts", systemImage: "network") {
            MenuBarContent(viewModel: vm, privilege: priv)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
