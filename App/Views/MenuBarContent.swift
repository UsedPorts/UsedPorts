import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let top = viewModel.visibleEntries.prefix(8)
        VStack(alignment: .leading) {
            Text("\(viewModel.rawEntries.count) ports").bold()
            Divider()
            if top.isEmpty {
                Text("(no ports)").foregroundStyle(.secondary)
            } else {
                ForEach(Array(top), id: \.id) { e in
                    Text("\(e.proto.rawValue) \(e.port) — \(e.processName) (pid \(e.pid))")
                        .font(.system(.body, design: .monospaced))
                }
            }
            Divider()
            Button("Show All Ports…") { openWindow(id: "main") }
                .keyboardShortcut("o")
            Button("Refresh") { Task { try? await viewModel.refreshOnce() } }
                .keyboardShortcut("r")
            Toggle("Auto-refresh", isOn: $viewModel.autoRefresh)
            Toggle("sudo mode", isOn: Binding(
                get: { privilege.isSudoActive },
                set: { on in
                    Task { on ? await privilege.enableSudo() : await privilege.disableSudo() }
                }))
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 360)
        .task { viewModel.bootstrapIfNeeded() }
    }
}
