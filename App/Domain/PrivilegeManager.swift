import Foundation
import Darwin

@MainActor
public final class PrivilegeManager: ObservableObject {
    @Published public private(set) var isSudoActive: Bool = false
    @Published public var lastError: String? = nil

    private let helper = ElevatedHelper()
    private let scanner: PortScanner

    public init(scanner: PortScanner) {
        self.scanner = scanner
    }

    public func enableSudo() async {
        guard let path = Bundle.main.url(forResource: "uph", withExtension: nil)?.path else {
            lastError = "uph 바이너리를 찾을 수 없습니다"
            return
        }
        do {
            try await helper.start(helperPath: path)
            let h = helper
            await scanner.setElevatedScanner { @Sendable in
                let req = HelperRequest(id: UUID().uuidString, op: .scan)
                let resp = try await h.send(req)
                guard resp.ok, let entries = resp.entries else {
                    throw HelperError.notRunning
                }
                return entries
            }
            isSudoActive = true
            lastError = nil
        } catch HelperError.userCancelled {
            lastError = "권한 부여가 취소되었습니다"
            isSudoActive = false
        } catch {
            lastError = "헬퍼 시작 실패: \(error)"
            isSudoActive = false
        }
    }

    public func disableSudo() async {
        await scanner.setElevatedScanner(nil)
        await helper.stop()
        isSudoActive = false
    }

    /// Kill via the helper (called only in sudo mode). Converts the result to KillOutcome.
    public func sudoKill(pid: Int32, sig: Int32) async -> KillOutcome {
        let req = HelperRequest(id: UUID().uuidString, op: .kill, pid: pid, sig: sig)
        do {
            let resp = try await helper.send(req)
            if resp.ok { return .terminated }
            if let e = resp.errno {
                switch e {
                case ESRCH: return .alreadyDead
                case EPERM: return .noPermission
                default: return .launchError("errno=\(e)")
                }
            }
            return .launchError(resp.message ?? "unknown")
        } catch {
            return .launchError("\(error)")
        }
    }
}
