import Foundation
import Darwin

@MainActor
public final class PrivilegeManager: ObservableObject {
    @Published public private(set) var isSudoActive: Bool = false
    @Published public var lastError: String? = nil

    private let helper = ElevatedHelper()
    private let scanner: PortScanner
    private let toasts: ToastCenter?
    private let logStore: LogStore?

    public init(scanner: PortScanner, toasts: ToastCenter? = nil, logStore: LogStore? = nil) {
        self.scanner = scanner
        self.toasts = toasts
        self.logStore = logStore
    }

    public func enableSudo() async {
        guard let path = Bundle.main.url(forResource: "uph", withExtension: nil)?.path else {
            lastError = String(localized: "uph helper binary not found")
            toasts?.showBanner(lastError)
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
            toasts?.showBanner(nil)
        } catch HelperError.userCancelled {
            lastError = String(localized: "Authorization cancelled")
            isSudoActive = false
            toasts?.showBanner(lastError)
            logStore?.warning("sudo enable: user cancelled authorization")
        } catch HelperError.fifoFailed(let m) {
            lastError = String(localized: "IPC channel setup failed: \(m)")
            isSudoActive = false
            toasts?.showBanner(lastError)
            logStore?.error("sudo enable: FIFO setup failed: \(m)")
        } catch {
            lastError = String(localized: "Helper failed to start: \(String(describing: error))")
            isSudoActive = false
            toasts?.showBanner(lastError)
            logStore?.error("sudo enable: helper start failed: \(error)")
        }
    }

    public func disableSudo() async {
        await scanner.setElevatedScanner(nil)
        await helper.stop()
        isSudoActive = false
        toasts?.showBanner(nil)
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
