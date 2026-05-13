import SwiftUI

@MainActor
struct DetailPaneView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @State private var augmented: PortEntry? = nil
    @State private var augmenting = false
    @State private var toast: String? = nil
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
            if let toast {
                Text(toast).padding(6).background(.thinMaterial).cornerRadius(6)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: viewModel.selection) { _, _ in refreshAugment() }
        .alert(item: $killConfirm) { intent in
            Alert(
                title: Text(intent.signal == .kill ? "SIGKILL 보내시겠습니까?" : "프로세스 종료"),
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
        case .terminated:   msg = "✓ Killed PID \(pid) (\(label))"
        case .alreadyDead:  msg = "이미 종료된 프로세스"
        case .noPermission: msg = "권한 부족 — sudo 모드 전환이 필요합니다"
        case .stillAlive:
            if signal == .term {
                killConfirm = KillIntent(pid: pid, label: label, signal: .kill)
                return
            } else { msg = "응답하지 않음 (Kill -9 실패)" }
        case .launchError(let m): msg = "오류: \(m)"
        }
        toast = msg
        try? await viewModel.refreshOnce()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        toast = nil
    }
}

struct KillIntent: Identifiable {
    let id = UUID()
    let pid: Int32
    let label: String
    let signal: KillSignal
}
