import SwiftUI

@MainActor
struct DetailPaneView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @ObservedObject var toasts: ToastCenter
    @ObservedObject var settings: AppSettings
    @State private var augmented: PortEntry? = nil
    @State private var augmenting = false
    @State private var killConfirm: KillIntent? = nil

    private let augmenter = ProcessAugmenter()
    private let killer = KillSupervisor()

    var body: some View {
        baseStack
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: viewModel.selection) { _, _ in refreshAugment() }
            .alert(item: $killConfirm, content: killAlert)
    }

    private var baseStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
    }

    private func killAlert(intent: KillIntent) -> Alert {
        let title: String = intent.signal == .kill ? "Send SIGKILL?" : "Terminate process"
        let message: String = "PID \(intent.pid) (\(intent.label))"
        let primaryLabel: String = intent.signal == .kill ? "Force Kill" : "Kill"
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: .destructive(Text(primaryLabel)) {
                Task { await performKill(pid: intent.pid, signal: intent.signal, label: intent.label) }
            },
            secondaryButton: .cancel()
        )
    }

    @ViewBuilder
    private var content: some View {
        let selected = selectedEntries
        if selected.isEmpty {
            Text("Select a row to see details")
                .foregroundStyle(.secondary)
                .padding()
        } else if selected.count == 1 {
            singleDetail(for: selected[0])
        } else {
            multiDetail(for: selected)
        }
    }

    private var selectedEntries: [PortEntry] {
        var byId: [PortEntry.ID: PortEntry] = [:]
        for entry in viewModel.rawEntries {
            byId[entry.id] = entry
        }
        if let aug = augmented {
            byId[aug.id] = aug
        }
        let picked = viewModel.selection.compactMap { byId[$0] }
        return picked.sorted { $0.port < $1.port }
    }

    // MARK: - Single

    private func singleDetail(for e: PortEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            singleHeader(for: e)
            singleActions(for: e)
        }
    }

    @ViewBuilder
    private func singleHeader(for e: PortEntry) -> some View {
        pathRow(for: e)
        cwdRow(for: e)
        userRow(for: e)
    }

    private func pathRow(for e: PortEntry) -> some View {
        let pathText: String = e.executablePath ?? (augmenting ? "loading…" : "—")
        return HStack {
            Text("Path:").bold()
            Text(pathText)
        }
    }

    private func cwdRow(for e: PortEntry) -> some View {
        let cwdText: String = e.cwd ?? "—"
        return HStack {
            Text("CWD:").bold()
            Text(cwdText)
        }
    }

    @ViewBuilder
    private func userRow(for e: PortEntry) -> some View {
        HStack {
            Text("User:").bold()
            Text(e.user)
            Spacer()
            startedLabel(for: e)
        }
    }

    @ViewBuilder
    private func startedLabel(for e: PortEntry) -> some View {
        if let st = e.startTime {
            let started: String = st.formatted(date: .abbreviated, time: .standard)
            Text("Started: \(started)")
        }
    }

    @ViewBuilder
    private func singleActions(for e: PortEntry) -> some View {
        HStack(spacing: 6) {
            singleCopyButtons(for: e)
            revealButton(for: e)
            pinButton(for: e)
            Spacer()
            singleKillButtons(for: e)
        }
    }

    @ViewBuilder
    private func singleCopyButtons(for e: PortEntry) -> some View {
        copyPidButton(for: e)
        copyPortButton(for: e)
        copyPathButton(for: e)
        copyAllSingleButton(for: e)
    }

    private func copyPidButton(for e: PortEntry) -> some View {
        let pidString: String = "\(e.pid)"
        return Button("Copy PID") { RowActions.copyToClipboard(pidString) }
    }

    private func copyPortButton(for e: PortEntry) -> some View {
        let portString: String = "\(e.port)"
        return Button("Copy Port") { RowActions.copyToClipboard(portString) }
    }

    private func copyPathButton(for e: PortEntry) -> some View {
        let path: String = e.executablePath ?? ""
        let disabled: Bool = e.executablePath == nil
        return Button("Copy Path") { RowActions.copyToClipboard(path) }
            .disabled(disabled)
    }

    private func copyAllSingleButton(for e: PortEntry) -> some View {
        Button("Copy All") {
            let tsv = PortEntryFormatter.tsv(for: [e])
            RowActions.copyToClipboard(tsv)
            let msg = NSLocalizedString("Copied 1 row", comment: "")
            toasts.showToast(msg)
        }
    }

    private func revealButton(for e: PortEntry) -> some View {
        let disabled: Bool = e.executablePath == nil
        return Button("Reveal in Finder") {
            if let p = e.executablePath { RowActions.revealInFinder(path: p) }
        }
        .disabled(disabled)
    }

    @ViewBuilder
    private func singleKillButtons(for e: PortEntry) -> some View {
        let protected: Bool = RowActions.isProtected(pid: e.pid)
        Button("Kill") {
            killConfirm = KillIntent(pid: e.pid, label: e.processName, signal: .term)
        }
        .disabled(protected)
        Button("Force Kill") {
            killConfirm = KillIntent(pid: e.pid, label: e.processName, signal: .kill)
        }
        .disabled(protected)
    }

    // MARK: - Multi

    private func multiDetail(for entries: [PortEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            multiHeader(for: entries)
            multiActions(for: entries)
        }
    }

    @ViewBuilder
    private func multiHeader(for entries: [PortEntry]) -> some View {
        multiCountLabel(count: entries.count)
        multiSummary(for: entries)
    }

    private func multiCountLabel(count: Int) -> some View {
        let label: String = "\(count) rows selected"
        return Text(label).bold()
    }

    private func multiSummary(for entries: [PortEntry]) -> some View {
        let summary: String = entries.prefix(20)
            .map { "\($0.port)/\($0.proto.rawValue)" }
            .joined(separator: ", ")
        return ScrollView(.horizontal, showsIndicators: false) {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func multiActions(for entries: [PortEntry]) -> some View {
        HStack(spacing: 6) {
            multiCopyButtons(for: entries)
            pinAllButton(for: entries)
            Spacer()
            multiBulkButtons(for: entries)
        }
    }

    @ViewBuilder
    private func multiCopyButtons(for entries: [PortEntry]) -> some View {
        copyAllMultiButton(for: entries)
        copyPidsButton(for: entries)
        copyPortsButton(for: entries)
    }

    private func copyAllMultiButton(for entries: [PortEntry]) -> some View {
        let count: Int = entries.count
        return Button("Copy All (TSV)") {
            let tsv = PortEntryFormatter.tsv(for: entries)
            RowActions.copyToClipboard(tsv)
            let fmt = NSLocalizedString("Copied %lld rows", comment: "")
            let msg = String(format: fmt, count)
            toasts.showToast(msg)
        }
    }

    private func copyPortsButton(for entries: [PortEntry]) -> some View {
        Button("Copy Ports") {
            let joined = entries.map { "\($0.port)" }.joined(separator: ",")
            RowActions.copyToClipboard(joined)
        }
    }

    private func copyPidsButton(for entries: [PortEntry]) -> some View {
        Button("Copy PIDs") {
            let joined = entries.map { "\($0.pid)" }.joined(separator: ",")
            RowActions.copyToClipboard(joined)
        }
    }

    @ViewBuilder
    private func multiBulkButtons(for entries: [PortEntry]) -> some View {
        killAllButton(for: entries)
        forceKillAllButton(for: entries)
    }

    @ViewBuilder
    private func pinAllButton(for entries: [PortEntry]) -> some View {
        let allPinned = !entries.isEmpty && entries.allSatisfy { settings.pinnedPorts.contains($0.port) }
        Button {
            if allPinned {
                for e in entries { settings.pinnedPorts.remove(e.port) }
            } else {
                for e in entries { settings.pinnedPorts.insert(e.port) }
            }
        } label: {
            if allPinned {
                Label("Unpin All from Menu Bar", systemImage: "pin.slash.fill")
            } else {
                Label("Pin All to Menu Bar", systemImage: "pin.fill")
            }
        }
    }

    private func killAllButton(for entries: [PortEntry]) -> some View {
        let allProtected: Bool = entries.allSatisfy { RowActions.isProtected(pid: $0.pid) }
        return Button("Kill All") {
            for e in entries where !RowActions.isProtected(pid: e.pid) {
                killConfirm = KillIntent(pid: e.pid, label: e.processName, signal: .term)
            }
        }
        .disabled(allProtected)
    }

    private func forceKillAllButton(for entries: [PortEntry]) -> some View {
        let allProtected: Bool = entries.allSatisfy { RowActions.isProtected(pid: $0.pid) }
        return Button("Force Kill All") {
            for e in entries where !RowActions.isProtected(pid: e.pid) {
                killConfirm = KillIntent(pid: e.pid, label: e.processName, signal: .kill)
            }
        }
        .disabled(allProtected)
    }

    @ViewBuilder
    private func pinButton(for e: PortEntry) -> some View {
        let pinned: Bool = settings.pinnedPorts.contains(e.port)
        let title: String = pinned
            ? String(localized: "Unpin from Menu Bar")
            : String(localized: "Pin to Menu Bar")
        let icon: String = pinned ? "pin.slash" : "pin"
        Button {
            settings.togglePin(port: e.port)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func refreshAugment() {
        augmented = nil
        guard viewModel.selection.count == 1,
              let id = viewModel.selection.first,
              let base = viewModel.rawEntries.first(where: { $0.id == id }) else { return }
        augmenting = true
        Task {
            let out = await augmenter.augment(base)
            await MainActor.run {
                augmented = out
                augmenting = false
            }
        }
    }

    private func performKill(pid: Int32, signal: KillSignal, label: String) async {
        let outcome: KillOutcome
        if privilege.isSudoActive {
            outcome = await privilege.sudoKill(pid: pid, sig: signal.rawValue)
        } else {
            outcome = await killer.kill(pid: pid, signal: signal)
        }
        let msg: String
        switch outcome {
        case .terminated:
            let fmt = NSLocalizedString("Killed PID %lld (%@)", comment: "")
            msg = String(format: fmt, Int(pid), label)
        case .alreadyDead:
            msg = NSLocalizedString("Already terminated", comment: "")
        case .noPermission:
            msg = NSLocalizedString("Permission denied — switch to sudo mode", comment: "")
        case .stillAlive:
            if signal == .term {
                killConfirm = KillIntent(pid: pid, label: label, signal: .kill)
                return
            } else {
                msg = NSLocalizedString("Not responding (Kill -9 failed)", comment: "")
            }
        case .launchError(let m):
            let fmt = NSLocalizedString("Error: %@", comment: "")
            msg = String(format: fmt, m)
        }
        toasts.showToast(msg)
        try? await viewModel.refreshOnce()
    }
}

struct KillIntent: Identifiable {
    let id = UUID()
    let pid: Int32
    let label: String
    let signal: KillSignal
}

/// Serializes selected PortEntries to TSV or a human-readable table.
enum PortEntryFormatter {
    /// Tab-separated table format — paste-friendly for spreadsheets and notes.
    /// Column order matches the main table's default arrangement so the clipboard
    /// payload reads top-to-bottom the same way the user sees the rows on screen.
    static func tsv(for entries: [PortEntry]) -> String {
        let header = "PID\tPort\tProcess\tProto\tIP\tAddress\tState\tUser\tStarted\tPath\tCWD"
        var lines: [String] = [header]
        for e in entries {
            lines.append(row(for: e))
        }
        return lines.joined(separator: "\n")
    }

    private static func row(for e: PortEntry) -> String {
        let pid: String = sanitize("\(e.pid)")
        let port: String = sanitize("\(e.port)")
        let processName: String = sanitize(e.processName)
        let proto: String = sanitize(e.proto.rawValue)
        let family: String = sanitize(e.ipFamily?.rawValue ?? "")
        let address: String = sanitize(e.localAddress)
        let state: String = sanitize(e.state ?? "")
        let user: String = sanitize(e.user)
        let started: String = sanitize(formatStarted(e.startTime))
        let path: String = sanitize(e.executablePath ?? "")
        let cwd: String = sanitize(e.cwd ?? "")

        var line: String = ""
        line += pid;          line += "\t"
        line += port;         line += "\t"
        line += processName;  line += "\t"
        line += proto;        line += "\t"
        line += family;       line += "\t"
        line += address;      line += "\t"
        line += state;        line += "\t"
        line += user;         line += "\t"
        line += started;      line += "\t"
        line += path;         line += "\t"
        line += cwd
        return line
    }

    private static func formatStarted(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private static func sanitize(_ s: String) -> String {
        return s.replacingOccurrences(of: "\t", with: " ")
    }
}
