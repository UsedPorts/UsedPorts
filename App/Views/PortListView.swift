import SwiftUI

struct PortListView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            PortListTable(viewModel: viewModel)
            Divider()
            // DetailPane은 Task 16에서. 자리표시자.
            placeholderDetail
        }
        .task { viewModel.startStream() }
        .onDisappear { Task { await viewModel.stopStream() } }
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

    private var placeholderDetail: some View {
        Text(viewModel.selection.map { "Selected: \($0)" } ?? "Select a row")
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
