import Foundation

public enum HelperError: Error, Equatable {
    case notRunning
    case spawnFailed(String)
    case userCancelled
    case timeout
}

public actor ElevatedHelper {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var pending: [String: CheckedContinuation<HelperResponse, Error>] = [:]
    private var readerTask: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { process?.isRunning ?? false }

    public func start(helperPath: String) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = helperPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "exec \(escaped)" with administrator privileges
        """
        proc.arguments = ["-e", script]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            throw HelperError.spawnFailed("\(error)")
        }
        self.process = proc
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading
        startReader()

        // 시작 확인용 ping
        do {
            _ = try await send(HelperRequest(id: UUID().uuidString, op: .ping), timeout: 30.0)
        } catch {
            await stop()
            throw HelperError.userCancelled
        }
    }

    public func stop() async {
        readerTask?.cancel()
        readerTask = nil
        if let sin = stdin { try? sin.close() }
        process?.terminate()
        process = nil; stdin = nil; stdout = nil
        for (_, cont) in pending {
            cont.resume(throwing: HelperError.notRunning)
        }
        pending.removeAll()
    }

    public func send(_ req: HelperRequest, timeout: TimeInterval = 5.0) async throws -> HelperResponse {
        guard let sin = stdin else { throw HelperError.notRunning }
        let line = try HelperCodec.encodeLine(req)
        let reqId = req.id
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HelperResponse, Error>) in
            pending[reqId] = cont
            do {
                try sin.write(contentsOf: line)
                let ns = UInt64(timeout * 1_000_000_000)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: ns)
                    guard let self else { return }
                    if let c = await self.pendingTake(id: reqId) {
                        c.resume(throwing: HelperError.timeout)
                    }
                }
            } catch {
                if let c = pending.removeValue(forKey: reqId) {
                    c.resume(throwing: error)
                }
            }
        }
    }

    private func pendingTake(id: String) -> CheckedContinuation<HelperResponse, Error>? {
        pending.removeValue(forKey: id)
    }

    private func startReader() {
        guard let out = stdout else { return }
        readerTask = Task.detached(priority: .utility) { [weak self] in
            var buffer = Data()
            while !Task.isCancelled {
                let chunk = out.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    if let resp = try? HelperCodec.decode(HelperResponse.self, from: lineData) {
                        await self?.deliver(resp)
                    }
                }
            }
        }
    }

    private func deliver(_ resp: HelperResponse) {
        if let cont = pending.removeValue(forKey: resp.id) {
            cont.resume(returning: resp)
        }
    }
}
