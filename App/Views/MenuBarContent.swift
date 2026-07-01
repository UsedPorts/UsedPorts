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
            Image("MenuBarIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("UsedPorts")
                        .font(.headline)
                    Text(AppVersion.display)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                leafRowView(item)
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
            ForEach(recentRows) { row in
                menuRowView(row)
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
            ForEach(searchRows) { row in
                menuRowView(row)
            }
        } else if pinnablePortFromQuery == nil {
            Text("(no matches)")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func menuRowView(_ row: MenuBarRow) -> some View {
        switch row {
        case .leaf(let item): leafRowView(item)
        case .group(let group): groupRowView(group)
        }
    }

    @ViewBuilder
    private func leafRowView(_ item: AnnotatedRow) -> some View {
        let row = item.row
        let confirming = (confirmKillRowId == row.id) && row.isActive
        PortRow(
            row: row,
            showProcessLine: !item.hideProcess,
            showIcon: settings.showProcessIcons,
            icon: settings.showProcessIcons ? viewModel.processIcon(forPID: pid_t(row.pid)) : nil,
            showKillButton: true,
            leadingIndent: 0,
            isPinned: settings.pinnedPorts.contains(row.port),
            isConfirming: confirming,
            onTogglePin: { settings.togglePin(port: row.port) },
            onKillRequest: { confirmKillRowId = row.id }
        )
        if confirming {
            KillConfirmBar(
                pid: row.pid,
                onCancel: { confirmKillRowId = nil },
                onKill: { performKill(pid: Int32(row.pid), label: row.processName, force: false) },
                onForceKill: { performKill(pid: Int32(row.pid), label: row.processName, force: true) }
            )
        }
    }

    /// Header + indented child rows. The header carries the process · pid label and the kill
    /// button (one kill per PID, matching how `kill(2)` actually behaves); each child carries
    /// its own pin button so the user can still pin specific ports without disabling grouping.
    @ViewBuilder
    private func groupRowView(_ group: GroupRowData) -> some View {
        let confirming = confirmKillRowId == group.id
        PortGroupHeader(
            processName: group.processName,
            pid: group.pid,
            portCount: group.children.count,
            showIcon: settings.showProcessIcons,
            icon: settings.showProcessIcons ? viewModel.processIcon(forPID: pid_t(group.pid)) : nil,
            isConfirming: confirming,
            onKillRequest: { confirmKillRowId = group.id }
        )
        if confirming {
            KillConfirmBar(
                pid: group.pid,
                onCancel: { confirmKillRowId = nil },
                onKill: { performKill(pid: Int32(group.pid), label: group.processName, force: false) },
                onForceKill: { performKill(pid: Int32(group.pid), label: group.processName, force: true) }
            )
        }
        ForEach(group.children) { child in
            PortRow(
                row: child,
                showProcessLine: false,
                showIcon: false,
                icon: nil,
                showKillButton: false,
                leadingIndent: 16,
                isPinned: settings.pinnedPorts.contains(child.port),
                isConfirming: false,
                onTogglePin: { settings.togglePin(port: child.port) },
                onKillRequest: {}
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

    private var recentRows: [MenuBarRow] {
        let pinnedSet = settings.pinnedPorts
        let entries = dedupedForMenuBar(viewModel.visibleEntries.filter { !pinnedSet.contains($0.port) })
        let rows = entries.sorted(by: Self.stablePortOrder)
            .map {
                PortRowData(id: $0.id, port: $0.port, proto: $0.proto.rawValue, processName: $0.processName, pid: Int($0.pid), state: $0.state, isActive: true)
            }
        return buildMenuRows(rows)
    }

    private var searchRows: [MenuBarRow] {
        var state = FilterState()
        state.globalSearch = query
        let entries = dedupedForMenuBar(viewModel.rawEntries.filter { PortListViewModel.matches(state, $0) })
        let rows = entries.sorted(by: Self.stablePortOrder)
            .map {
                PortRowData(id: $0.id, port: $0.port, proto: $0.proto.rawValue,
                            processName: $0.processName, pid: Int($0.pid),
                            state: $0.state, isActive: true)
            }
        return buildMenuRows(rows)
    }

    /// When `hideDuplicateRows` is on, collapse the menubar list on a coarser key than the
    /// main table — only (pid, proto, port). The popover doesn't expose address/state/user
    /// columns, so two rows differing only on those would look identical to the user; this
    /// keeps the dense menubar list free of visual duplicates without affecting the table.
    private func dedupedForMenuBar(_ entries: [PortEntry]) -> [PortEntry] {
        guard settings.hideDuplicateRows else { return entries }
        var seen: Set<String> = []
        var out: [PortEntry] = []
        out.reserveCapacity(entries.count)
        for e in entries {
            let key = "\(e.pid)\u{1F}\(e.proto.rawValue)\u{1F}\(e.port)"
            if seen.insert(key).inserted {
                out.append(e)
            }
        }
        return out
    }

    /// Port ascending with `(pid, id)` tie-breakers. `Array.sorted(by:)` is stable, but stability
    /// only preserves the *input* order — and our input comes from `lsof`, which doesn't guarantee
    /// a deterministic order for entries sharing the same port (different PIDs or dup'd fds). Without
    /// a tie-breaker, same-port rows would visibly swap places between refreshes.
    private static func stablePortOrder(_ lhs: PortEntry, _ rhs: PortEntry) -> Bool {
        if lhs.port != rhs.port { return lhs.port < rhs.port }
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.id < rhs.id
    }

    /// Bridges the menubar list to the same `groupByPid` setting that powers the main table.
    /// When on, every PID renders as a process · pid header followed by indented child rows
    /// (one per port), including PIDs that own a single port — so the process name, icon, and
    /// pid are always visible in grouping mode. When off, falls back to the flat layout —
    /// `menuBarGroupSamePid` still hides the repeated process · pid line on adjacent same-PID
    /// rows so the two modes look visually similar.
    private func buildMenuRows(_ rows: [PortRowData]) -> [MenuBarRow] {
        guard settings.groupByPid else {
            return annotateGrouping(rows).map { .leaf($0) }
        }
        var seenPids: Set<Int> = []
        var pidOrder: [Int] = []
        var byPid: [Int: [PortRowData]] = [:]
        var orphans: [PortRowData] = []
        for row in rows {
            guard row.pid > 0 else {
                orphans.append(row)
                continue
            }
            if seenPids.insert(row.pid).inserted {
                pidOrder.append(row.pid)
            }
            byPid[row.pid, default: []].append(row)
        }
        var out: [MenuBarRow] = []
        for pid in pidOrder {
            let members = byPid[pid] ?? []
            guard let first = members.first else { continue }
            // Group every PID uniformly, including single-port ones, so grouping mode
            // always shows the process · pid header (icon + name + pid + "1 port")
            // above the port row instead of a bare leaf.
            out.append(.group(GroupRowData(
                id: "group-\(pid)",
                pid: pid,
                processName: first.processName,
                children: members
            )))
        }
        for row in orphans {
            out.append(.leaf(AnnotatedRow(row: row, hideProcess: false)))
        }
        return out
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

    private func performKill(pid: Int32, label: String, force: Bool) {
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

private struct GroupRowData: Identifiable, Equatable {
    let id: String
    let pid: Int
    let processName: String
    let children: [PortRowData]
}

private enum MenuBarRow: Identifiable, Equatable {
    case leaf(AnnotatedRow)
    case group(GroupRowData)

    var id: String {
        switch self {
        case .leaf(let item): return item.id
        case .group(let group): return group.id
        }
    }
}

/// Single port row. Used in two roles: standalone leaf (Pinned/Search/OFF mode, and orphan
/// rows with no PID), and indented child of a `PortGroupHeader` (every grouped PID, including
/// single-port ones). The header role hides the per-row process line and kill button so the
/// PID-level controls live on the header; both roles share the same port/proto/state line so the
/// list keeps a consistent visual rhythm between ON and OFF.
/// Process app icon, or a same-size transparent slot when the process has none
/// (CLI/daemon), so process names stay aligned whether or not an icon resolves.
private struct ProcessIconBadge: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        }
    }
}

private struct PortRow: View {
    let row: PortRowData
    let showProcessLine: Bool
    let showIcon: Bool
    let icon: NSImage?
    let showKillButton: Bool
    let leadingIndent: CGFloat
    let isPinned: Bool
    let isConfirming: Bool
    let onTogglePin: () -> Void
    let onKillRequest: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            statusDot
            protoBadge
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("\(row.port)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(row.isActive ? .primary : .tertiary)
                    if let state = row.state, !state.isEmpty {
                        Text(state)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if showProcessLine {
                    HStack(spacing: 4) {
                        if showIcon { ProcessIconBadge(icon: icon, size: 13) }
                        Text(processLine)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            Spacer(minLength: 4)
            actionButtons
        }
        .padding(.leading, 8 + leadingIndent)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var processLine: String {
        if row.isActive && row.pid > 0 {
            return "\(row.processName) · pid \(row.pid)"
        }
        return row.processName
    }

    private var rowBackground: Color {
        if isConfirming { return Color.red.opacity(0.08) }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }

    private var canKill: Bool {
        row.isActive && row.pid > 0 && !RowActions.isProtected(pid: Int32(row.pid))
    }

    private var actionButtons: some View {
        // Render with opacity toggles so layout doesn't shift on hover. Pin is always visible
        // when pinned (so the user sees their state); kill is hover-only to keep the row clean.
        let pinVisible = isHovering || isPinned
        let killVisible = showKillButton && isHovering && canKill
        return HStack(spacing: 6) {
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(pinVisible ? 1 : 0)
            .allowsHitTesting(pinVisible)
            .help(isPinned ? String(localized: "Unpin from menu bar") : String(localized: "Pin to menu bar"))

            if showKillButton {
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

/// PID-level header for a grouped block. Hosts the process · pid label and the kill button so
/// the child rows below stay focused on their port-specific information.
private struct PortGroupHeader: View {
    let processName: String
    let pid: Int
    let portCount: Int
    let showIcon: Bool
    let icon: NSImage?
    let isConfirming: Bool
    let onKillRequest: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if showIcon { ProcessIconBadge(icon: icon, size: 15) }
            Text(processName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("pid \(pid)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(portsSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            killButton
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var portsSummary: String {
        let portsWord = portCount == 1
            ? NSLocalizedString("port", comment: "singular")
            : NSLocalizedString("ports", comment: "plural")
        return "\(portCount) \(portsWord)"
    }

    private var rowBackground: Color {
        if isConfirming { return Color.red.opacity(0.08) }
        return isHovering ? Color.primary.opacity(0.04) : .clear
    }

    private var canKill: Bool {
        pid > 0 && !RowActions.isProtected(pid: Int32(pid))
    }

    private var killButton: some View {
        let visible = isHovering && canKill
        return Button(action: onKillRequest) {
            Image(systemName: "stop.circle")
                .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .help(String(localized: "Kill process"))
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
