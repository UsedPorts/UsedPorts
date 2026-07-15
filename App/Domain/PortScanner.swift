import Foundation

public protocol PortScanning: AnyObject, Sendable {
    func scanOnce() async throws -> [PortEntry]
    func startPolling(intervalSeconds: TimeInterval, immediateFirstScan: Bool) async -> AsyncStream<[PortEntry]>
    func stopPolling() async
}

public actor PortScanner: PortScanning {
    private let runner: CommandRunning
    private let parser: LsofParser
    private var pollTask: Task<Void, Never>?
    private var continuation: AsyncStream<[PortEntry]>.Continuation?

    public var elevatedScanner: (@Sendable () async throws -> [PortEntry])?

    public init(runner: CommandRunning = CommandRunner(), parser: LsofParser = LsofParser()) {
        self.runner = runner
        self.parser = parser
    }

    public func setElevatedScanner(_ fn: (@Sendable () async throws -> [PortEntry])?) {
        self.elevatedScanner = fn
    }

    public func scanOnce() async throws -> [PortEntry] {
        if let elevated = elevatedScanner {
            return try await elevated()
        }
        let r = try await runner.run(
            "/usr/sbin/lsof",
            args: ["-nP", "-iTCP", "-iUDP", "-F", "pcuLnPTt"],
            timeout: 2.0
        )
        return parser.parse(r.stdoutString)
    }

    public func startPolling(intervalSeconds: TimeInterval, immediateFirstScan: Bool = true) -> AsyncStream<[PortEntry]> {
        pollTask?.cancel()
        continuation?.finish()
        let stream = AsyncStream<[PortEntry]> { cont in
            self.continuation = cont
        }
        pollTask = Task { [weak self] in
            // Skip the leading scan when rescheduling cadence (e.g. window hidden) so a
            // visibility change doesn't cost an immediate scan + UI rebuild.
            if !immediateFirstScan {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
            while !Task.isCancelled {
                guard let self else { break }
                // Re-check cancellation after the scan: cancelling mid-scan terminates
                // lsof and CommandRunner returns its *partial* output. `continuation` is
                // an instance property, so a cancelled poll task from before a stream
                // restart would otherwise yield that truncated batch into the NEW stream —
                // ports briefly "disappear", which flaps the UI and fires spurious
                // pinned-port notifications.
                if let entries = try? await self.scanOnce(), !Task.isCancelled {
                    await self.yield(entries)
                }
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
        return stream
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func yield(_ entries: [PortEntry]) {
        continuation?.yield(entries)
    }
}
