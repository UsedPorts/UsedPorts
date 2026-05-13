import Foundation
import Darwin

public enum KillSignal: Int32 {
    case term = 15
    case kill = 9
}

public enum KillOutcome: Equatable {
    case terminated
    case alreadyDead
    case noPermission
    case stillAlive
    case launchError(String)
}

public protocol KillExecuting: Sendable {
    func sendSignal(_ pid: Int32, sig: Int32) -> Int32
    func isAlive(_ pid: Int32) -> Bool
}

public struct SystemKillExecutor: KillExecuting {
    public init() {}
    public func sendSignal(_ pid: Int32, sig: Int32) -> Int32 {
        let r = Darwin.kill(pid, sig)
        return r == 0 ? 0 : errno
    }
    public func isAlive(_ pid: Int32) -> Bool {
        let r = Darwin.kill(pid, 0)
        if r == 0 { return true }
        return errno != ESRCH
    }
}

public struct KillSupervisor: Sendable {
    public let executor: KillExecuting
    public let sleep: @Sendable (TimeInterval) async -> Void

    public init(
        executor: KillExecuting = SystemKillExecutor(),
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.executor = executor
        self.sleep = sleep
    }

    public func kill(pid: Int32, signal: KillSignal, timeoutSeconds: TimeInterval = 3.0, pollInterval: TimeInterval = 0.25) async -> KillOutcome {
        let err = executor.sendSignal(pid, sig: signal.rawValue)
        if err != 0 {
            switch err {
            case ESRCH: return .alreadyDead
            case EPERM: return .noPermission
            default: return .launchError("errno=\(err)")
            }
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if !executor.isAlive(pid) { return .terminated }
            await sleep(pollInterval)
        }
        return executor.isAlive(pid) ? .stillAlive : .terminated
    }
}
