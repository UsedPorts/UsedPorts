import Foundation

public protocol PortScanning: AnyObject, Sendable {
    func scanOnce() async throws -> [PortEntry]
    func startPolling(intervalSeconds: TimeInterval) async -> AsyncStream<[PortEntry]>
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

    public func startPolling(intervalSeconds: TimeInterval) -> AsyncStream<[PortEntry]> {
        pollTask?.cancel()
        continuation?.finish()
        let stream = AsyncStream<[PortEntry]> { cont in
            self.continuation = cont
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if let entries = try? await self.scanOnce() {
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
