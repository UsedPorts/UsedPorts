import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            controls
            Divider()
            footer
        }
        .frame(width: 400)
        .task { viewModel.bootstrapIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("UsedPorts")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if privilege.isSudoActive {
                Label("sudo", systemImage: "lock.shield.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        let total = viewModel.rawEntries.count
        let listening = viewModel.rawEntries.filter { $0.state == "LISTEN" }.count
        return "\(total) ports · \(listening) listening"
    }

    // MARK: - Content (pinned + top)

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !settings.pinnedPorts.isEmpty {
                    sectionLabel(String(localized: "Pinned"))
                    ForEach(pinnedRows) { row in
                        PortRow(row: row,
                                isPinned: true,
                                onTogglePin: { settings.togglePin(port: row.port) })
                    }
                    Divider().padding(.vertical, 4)
                }
                sectionLabel(String(localized: "Recent"))
                if recentRows.isEmpty {
                    Text("(no ports)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.vertical, 12)
                } else {
                    ForEach(recentRows) { row in
                        PortRow(row: row,
                                isPinned: settings.pinnedPorts.contains(row.port),
                                onTogglePin: { settings.togglePin(port: row.port) })
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .frame(maxHeight: 320)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
            Spacer()
        }
    }

    /// Row data for pinned ports. Uses the actual PortEntry if active, otherwise a placeholder row.
    private var pinnedRows: [PortRowData] {
        let map = Dictionary(grouping: viewModel.rawEntries, by: { $0.port })
        return settings.pinnedPorts.sorted().map { port in
            if let e = map[port]?.first {
                return PortRowData(id: "pin-\(port)", port: port, proto: e.proto.rawValue, processName: e.processName, pid: Int(e.pid), state: e.state, isActive: true)
            } else {
                return PortRowData(id: "pin-\(port)", port: port, proto: "—", processName: String(localized: "(inactive)"), pid: 0, state: nil, isActive: false)
            }
        }
    }

    private var recentRows: [PortRowData] {
        let pinnedSet = settings.pinnedPorts
        return viewModel.visibleEntries.prefix(12).filter { !pinnedSet.contains($0.port) }.map {
            PortRowData(id: $0.id, port: $0.port, proto: $0.proto.rawValue, processName: $0.processName, pid: Int($0.pid), state: $0.state, isActive: true)
        }
    }

    // MARK: - Controls (toggles)

    private var controls: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $viewModel.autoRefresh) {
                Label("Auto-refresh", systemImage: "arrow.clockwise")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Toggle(isOn: Binding(
                get: { privilege.isSudoActive },
                set: { on in
                    Task { on ? await privilege.enableSudo() : await privilege.disableSudo() }
                })) {
                Label("sudo", systemImage: "lock.shield")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Footer (actions)

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                openWindow(id: "main")
            } label: {
                Label("Show All Ports", systemImage: "macwindow")
            }
            .controlSize(.small)
            .keyboardShortcut("o")
            Button {
                Task { try? await viewModel.refreshOnce() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.small)
            .keyboardShortcut("r")
            .help("Refresh")
            Spacer()
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.small)
            .keyboardShortcut(",")
            .help("Settings…")
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.small)
            .keyboardShortcut("q")
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Row

private struct PortRowData: Identifiable, Equatable {
    let id: String
    let port: UInt16
    let proto: String
    let processName: String
    let pid: Int
    let state: String?
    let isActive: Bool
}

private struct PortRow: View {
    let row: PortRowData
    let isPinned: Bool
    let onTogglePin: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            protoBadge
            Text("\(row.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(row.isActive ? .primary : .tertiary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.processName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(row.isActive ? .primary : .secondary)
                if row.isActive {
                    Text("pid \(row.pid)" + (row.state.map { " · \($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isHovering || isPinned {
                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isPinned ? "Unpin from menu bar" : "Pin to menu bar")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var protoBadge: some View {
        let bg: Color = row.proto == "TCP" ? .blue : (row.proto == "UDP" ? .purple : .gray)
        Text(row.proto)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(bg.opacity(row.isActive ? 0.85 : 0.35))
            .clipShape(Capsule())
            .frame(width: 32)
    }
}
