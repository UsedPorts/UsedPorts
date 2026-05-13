import SwiftUI

struct PortListView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @ObservedObject var toasts: ToastCenter

    var body: some View {
        ToastHost(center: toasts) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                PortListTable(viewModel: viewModel)
                Divider()
                DetailPaneView(viewModel: viewModel, privilege: privilege, toasts: toasts)
            }
            .task { viewModel.startStream() }
            .onDisappear { Task { await viewModel.stopStream() } }
        }
    }

    private var toolbar: some View {
        HStack {
            TextField("Search PID, port, process…", text: $viewModel.filter.globalSearch)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Spacer()
            Toggle("Auto", isOn: $viewModel.autoRefresh)
                .toggleStyle(.switch)
                .onChange(of: viewModel.autoRefresh) { _, on in
                    if on { viewModel.startStream() } else { Task { await viewModel.stopStream() } }
                }
            Toggle("sudo", isOn: Binding(
                get: { privilege.isSudoActive },
                set: { on in
                    Task {
                        if on { await privilege.enableSudo() }
                        else { await privilege.disableSudo() }
                    }
                }
            )).toggleStyle(.switch)
            Button {
                Task { try? await viewModel.refreshOnce() }
            } label: { Image(systemName: "arrow.clockwise") }
                .help("새로고침 (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(8)
    }

}
