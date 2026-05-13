import SwiftUI

@MainActor
struct DetailPaneView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @ObservedObject var toasts: ToastCenter
    @State private var augmented: PortEntry? = nil
    @State private var augmenting = false
    @State private var killConfirm: KillIntent? = nil

    private let augmenter = ProcessAugmenter()
    private let killer = KillSupervisor()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let entry = currentEntry {
                detail(for: entry)
            } else {
                Text("Select a row to see details").foregroundStyle(.secondary).padding()
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: viewModel.selection) { _, _ in refreshAugment() }
        .alert(item: $killConfirm) { intent in
            Alert(
                title: Text(intent.signal == .kill ? "Send SIGKILL?" : "Terminate process"),
                message: Text("PID \(intent.pid) (\(intent.label))"),
                primaryButton: .destructive(Text(intent.signal == .kill ? "Kill -9" : "Kill")) {
                    Task { await performKill(pid: intent.pid, signal: intent.signal, label: intent.label) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var currentEntry: PortEntry? {
        if let aug = augmented, aug.id == viewModel.selection { return aug }
        guard let id = viewModel.selection else { return nil }
        return viewModel.rawEntries.first { $0.id == id }
    }

    private func detail(for e: PortEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Path:").bold()
                Text(e.executablePath ?? (augmenting ? "loading…" : "—"))
            }
            HStack { Text("CWD:").bold(); Text(e.cwd ?? "—") }
            HStack {
                Text("User:").bold(); Text(e.user)
                Spacer()
                if let st = e.startTime {
                    Text("Started: \(st.formatted(date: .abbreviated, time: .standard))")
                }
            }
            HStack(spacing: 6) {
                Button("Copy PID")  { RowActions.copyToClipboard("\(e.pid)") }
                Button("Copy Port") { RowActions.copyToClipboard("\(e.port)") }
                Button("Copy Path") { RowActions.copyToClipboard(e.executablePath ?? "") }
                    .disabled(e.executablePath == nil)
                Button("Reveal in Finder") {
                    if let p = e.executablePath { RowActions.revealInFinder(path: p) }
                }
                .disabled(e.executablePath == nil)
                Spacer()
                Button("Kill") {
                    killConfirm = KillIntent(pid: e.pid, label: e.processName, signal: .term)
                }
                .disabled(RowActions.isProtected(pid: e.pid))
                Button("Kill -9") {
                    killConfirm = KillIntent(pid: e.pid, label: e.processName, signal: .kill)
                }
                .disabled(RowActions.isProtected(pid: e.pid))
            }
        }
    }

    private func refreshAugment() {
        augmented = nil
        guard let id = viewModel.selection,
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
            msg = String(localized: "Killed PID \(Int(pid)) (\(label))")
        case .alreadyDead:
            msg = String(localized: "Already terminated")
        case .noPermission:
            msg = String(localized: "Permission denied — switch to sudo mode")
        case .stillAlive:
            if signal == .term {
                killConfirm = KillIntent(pid: pid, label: label, signal: .kill)
                return
            } else {
                msg = String(localized: "Not responding (Kill -9 failed)")
            }
        case .launchError(let m):
            msg = String(localized: "Error: \(m)")
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
