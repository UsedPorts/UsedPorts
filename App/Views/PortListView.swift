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
            .task {
                viewModel.bootstrapIfNeeded()
                viewModel.setWindowVisible(true)
            }
            .onAppear { viewModel.setWindowVisible(true) }
            .onDisappear { viewModel.setWindowVisible(false) }
        }
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 4) {
                TextField("Search PID, port, process…", text: $viewModel.filter.globalSearch)
                    .textFieldStyle(.roundedBorder)
                if !viewModel.filter.globalSearch.isEmpty {
                    Button {
                        viewModel.filter.globalSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("검색어 지우기")
                }
            }
            .frame(maxWidth: 320)
            Text("\(viewModel.visibleEntries.count) / \(viewModel.rawEntries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("표시 중 / 전체 항목 수")
            Spacer()
            Toggle("Auto", isOn: $viewModel.autoRefresh)
                .toggleStyle(.switch)
                .onChange(of: viewModel.autoRefresh) { _, on in
                    if on { viewModel.bootstrapIfNeeded() } else { Task { await viewModel.stopStream() } }
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
