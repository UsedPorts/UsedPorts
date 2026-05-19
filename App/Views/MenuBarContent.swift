import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var toasts: ToastCenter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var query: String = ""
    @State private var confirmKillRowId: String? = nil

    private let killer = KillSupervisor()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
            Divider()
            controls
            Divider()
            footer
        }
        .frame(width: 420)
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

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(String(localized: "Search PID, port, process…"), text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Content (fixed-height area keeps footer position stable)

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                if query.isEmpty {
                    defaultList
                } else {
                    searchList
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(height: 320)
    }

    @ViewBuilder
    private var defaultList: some View {
        if !settings.pinnedPorts.isEmpty {
            sectionLabel(String(localized: "Pinned"))
            ForEach(pinnedRows) { item in
                rowView(item)
            }
            Divider().padding(.vertical, 4)
        }
        sectionLabel(String(localized: "All"))
        if recentRows.isEmpty {
            Text("(no ports)")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.vertical, 12)
        } else {
            ForEach(recentRows) { item in
                rowView(item)
            }
        }
    }

    @ViewBuilder
    private var searchList: some View {
        if let portToPin = pinnablePortFromQuery {
            pinSuggestionRow(port: portToPin)
            if !searchRows.isEmpty {
                Divider().padding(.vertical, 4)
            }
        }
        if !searchRows.isEmpty {
            sectionLabel(String(localized: "Matches"))
            ForEach(searchRows) { item in
                rowView(item)
            }
        } else if pinnablePortFromQuery == nil {
            Text("(no matches)")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func rowView(_ item: AnnotatedRow) -> some View {
        let row = item.row
        let confirming = (confirmKillRowId == row.id) && row.isActive
        PortRow(
            row: row,
            hideProcess: item.hideProcess,
            isPinned: settings.pinnedPorts.contains(row.port),
            isConfirming: confirming,
            onTogglePin: { settings.togglePin(port: row.port) },
            onKillRequest: { confirmKillRowId = row.id }
        )
        if confirming {
            KillConfirmBar(
                pid: row.pid,
                onCancel: { confirmKillRowId = nil },
                onKill: { performKill(row: row, force: false) },
                onForceKill: { performKill(row: row, force: true) }
            )
        }
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

    // MARK: - Row data

    private var pinnedRows: [AnnotatedRow] {
        let map = Dictionary(grouping: viewModel.rawEntries, by: { $0.port })
        let rows: [PortRowData] = settings.pinnedPorts.sorted().map { port in
            if let e = map[port]?.first {
                return PortRowData(id: "pin-\(port)", port: port, proto: e.proto.rawValue, processName: e.processName, pid: Int(e.pid), state: e.state, isActive: true)
            } else {
                return PortRowData(id: "pin-\(port)", port: port, proto: "—", processName: String(localized: "(inactive)"), pid: 0, state: nil, isActive: false)
            }
        }
        return annotateGrouping(rows)
    }

    private var recentRows: [AnnotatedRow] {
        let pinnedSet = settings.pinnedPorts
        let rows = viewModel.visibleEntries.filter { !pinnedSet.contains($0.port) }
            .sorted { $0.port < $1.port }
            .map {
                PortRowData(id: $0.id, port: $0.port, proto: $0.proto.rawValue, processName: $0.processName, pid: Int($0.pid), state: $0.state, isActive: true)
            }
        return annotateGrouping(rows)
    }

    private var searchRows: [AnnotatedRow] {
        var state = FilterState()
        state.globalSearch = query
        let rows = viewModel.rawEntries
            .filter { PortListViewModel.matches(state, $0) }
            .sorted { $0.port < $1.port }
            .map {
                PortRowData(id: $0.id, port: $0.port, proto: $0.proto.rawValue,
                            processName: $0.processName, pid: Int($0.pid),
                            state: $0.state, isActive: true)
            }
        return annotateGrouping(rows)
    }

    /// Tag each row with whether its process name should be hidden. The "ports-only"
    /// menu-bar toggle controls only the NSStatusItem title (see `AppDelegate`), so
    /// popover rows always show process info; only "group same-process rows" hides
    /// the name on a row whose PID matches the row above.
    private func annotateGrouping(_ rows: [PortRowData]) -> [AnnotatedRow] {
        let group = settings.menuBarGroupSamePid
        var result: [AnnotatedRow] = []
        result.reserveCapacity(rows.count)
        var prevPid: Int? = nil
        for row in rows {
            let hide = group && prevPid == row.pid && row.pid > 0
            result.append(AnnotatedRow(row: row, hideProcess: hide))
            prevPid = row.pid
        }
        return result
    }

    /// When the query is purely a port number (1..65535) and that port isn't already pinned,
    /// expose a one-tap action to pin it — useful to watch arbitrary ports for activity.
    private var pinnablePortFromQuery: UInt16? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let n = Int(trimmed), (1...65535).contains(n) else { return nil }
        let port = UInt16(n)
        if settings.pinnedPorts.contains(port) { return nil }
        return port
    }

    @ViewBuilder
    private func pinSuggestionRow(port: UInt16) -> some View {
        let active = viewModel.rawEntries.contains(where: { $0.port == port })
        Button {
            settings.togglePin(port: port)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: NSLocalizedString("Pin port %lld to menu bar", comment: ""), Int(port)))
                        .foregroundStyle(.primary)
                    Text(active ? String(localized: "Currently active") : String(localized: "Currently inactive"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kill flow (inline confirmation, mirrors DetailPaneView's escalation)

    private func performKill(row: PortRowData, force: Bool) {
        let pid = Int32(row.pid)
        let label = row.processName
        confirmKillRowId = nil
        guard pid > 0, !RowActions.isProtected(pid: pid) else { return }
        let signal: KillSignal = force ? .kill : .term
        Task {
            let outcome: KillOutcome
            if privilege.isSudoActive {
                outcome = await privilege.sudoKill(pid: pid, sig: signal.rawValue)
            } else {
                outcome = await killer.kill(pid: pid, signal: signal)
            }
            let msg: String
            switch outcome {
            case .terminated:
                let fmt = force
                    ? NSLocalizedString("Killed PID %lld (%@) [-9]", comment: "")
                    : NSLocalizedString("Killed PID %lld (%@)", comment: "")
                msg = String(format: fmt, Int(pid), label)
            case .alreadyDead:
                msg = NSLocalizedString("Already terminated", comment: "")
            case .noPermission:
                msg = NSLocalizedString("Permission denied — switch to sudo mode", comment: "")
            case .stillAlive:
                if force {
                    msg = NSLocalizedString("Not responding (Kill -9 failed)", comment: "")
                } else {
                    let escalated: KillOutcome
                    if privilege.isSudoActive {
                        escalated = await privilege.sudoKill(pid: pid, sig: KillSignal.kill.rawValue)
                    } else {
                        escalated = await killer.kill(pid: pid, signal: .kill)
                    }
                    if case .terminated = escalated {
                        let fmt = NSLocalizedString("Killed PID %lld (%@) [-9]", comment: "")
                        msg = String(format: fmt, Int(pid), label)
                    } else {
                        msg = NSLocalizedString("Not responding (Kill -9 failed)", comment: "")
                    }
                }
            case .launchError(let m):
                let fmt = NSLocalizedString("Error: %@", comment: "")
                msg = String(format: fmt, m)
            }
            toasts.showToast(msg)
            try? await viewModel.refreshOnce()
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
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open UsedPorts", systemImage: "macwindow")
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
            .help(String(localized: "Refresh"))
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.small)
            .keyboardShortcut(",")
            .help(String(localized: "Settings…"))
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.small)
            .keyboardShortcut("q")
            .help(String(localized: "Quit"))
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

private struct AnnotatedRow: Identifiable, Equatable {
    let row: PortRowData
    let hideProcess: Bool
    var id: String { row.id }
}

private struct PortRow: View {
    let row: PortRowData
    let hideProcess: Bool
    let isPinned: Bool
    let isConfirming: Bool
    let onTogglePin: () -> Void
    let onKillRequest: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        normalView
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isConfirming { return Color.red.opacity(0.08) }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }

    private var canKill: Bool {
        row.isActive && row.pid > 0 && !RowActions.isProtected(pid: Int32(row.pid))
    }

    private var normalView: some View {
        HStack(spacing: 8) {
            statusDot
            protoBadge
            Text("\(row.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(row.isActive ? .primary : .tertiary)
                .frame(width: 56, alignment: .leading)
            if !hideProcess {
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
            }
            Spacer()
            actionButtons
        }
    }

    private var actionButtons: some View {
        // Always render the buttons so the row's layout doesn't shift when the
        // pointer enters/leaves; toggle visibility through opacity instead.
        let pinVisible = isHovering || isPinned
        let killVisible = isHovering && canKill
        return HStack(spacing: 6) {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(pinVisible ? 1 : 0)
            .allowsHitTesting(pinVisible)
            .help(isPinned ? String(localized: "Unpin from menu bar") : String(localized: "Pin to menu bar"))

            Button(action: onKillRequest) {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .opacity(killVisible ? 1 : 0)
            .allowsHitTesting(killVisible)
            .help(String(localized: "Kill process"))
        }
    }


    private var statusDot: some View {
        Image(systemName: row.isActive ? "circle.fill" : "circle")
            .font(.system(size: 8))
            .foregroundStyle(row.isActive ? Color.green : Color.secondary)
            .frame(width: 10)
            .help(row.isActive ? String(localized: "Active") : String(localized: "Inactive"))
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

private struct KillConfirmBar: View {
    let pid: Int
    let onCancel: () -> Void
    let onKill: () -> Void
    let onForceKill: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Kill PID \(pid)?")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(String(localized: "Cancel"), action: onCancel)
                .controlSize(.small)
            Button(action: onKill) {
                Text(String(localized: "Kill"))
            }
            .controlSize(.small)
            Button(role: .destructive, action: onForceKill) {
                Text(String(localized: "Force Kill"))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 4)
    }
}
