import SwiftUI

@main
struct UsedPortsApp: App {
    private let scanner: PortScanner
    @StateObject private var vm: PortListViewModel
    @StateObject private var priv: PrivilegeManager

    init() {
        let s = PortScanner()
        self.scanner = s
        _vm = StateObject(wrappedValue: PortListViewModel(scanner: s))
        _priv = StateObject(wrappedValue: PrivilegeManager(scanner: s))
    }

    var body: some Scene {
        WindowGroup("UsedPorts") {
            PortListView(viewModel: vm, privilege: priv)
                .frame(minWidth: 900, minHeight: 500)
        }
    }
}
