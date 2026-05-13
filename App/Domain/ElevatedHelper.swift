import Foundation
import Darwin

public enum HelperError: Error, Equatable {
    case notRunning
    case spawnFailed(String)
    case userCancelled
    case timeout
    case fifoFailed(String)
}

/// FIFO-based sudo helper IPC.
///
/// Background: The previous implementation captured stdin/stdout of
/// `osascript -e 'do shell script "exec uph" ...'` via Pipe, but AppleScript's
/// `do shell script` launches a separate root shell that does not inherit the
/// osascript process's pipes. The privilege dialog worked fine, but IPC was broken.
///
/// The new implementation creates two named pipes (FIFOs) in a user-owned temp
/// directory and delegates background launch to the elevated shell as
/// `uph <cmd.fifo >resp.fifo &`. osascript returns immediately, and subsequent
/// IPC flows through the FIFO FDs we hold directly.
public actor ElevatedHelper {
    private var tmpDir: String?
    private var cmdPath: String?
    private var respPath: String?
    private var cmdFD: Int32 = -1
    private var respFD: Int32 = -1
    private var pending: [String: CheckedContinuation<HelperResponse, Error>] = [:]
    private var readerTask: Task<Void, Never>?
    private var helperLaunched: Bool = false

    public init() {}

    public var isRunning: Bool { helperLaunched && cmdFD >= 0 }

    /// Production path: launches the helper as a root-privileged background process via osascript.
    public func start(helperPath: String) async throws {
        try await startInner(helperPath: helperPath, useSudo: true)
    }

    /// Test path: runs the helper as a child process with user privileges (no sudo).
    /// Intended for unit-testing the FIFO lifecycle itself.
    public func startForTesting(helperPath: String) async throws {
        try await startInner(helperPath: helperPath, useSudo: false)
    }

    private func startInner(helperPath: String, useSudo: Bool) async throws {
        // 1) Create a 0700 temp directory with mkdtemp.
        let template = "/tmp/UsedPorts-XXXXXX"
        var templateBytes = Array(template.utf8).map { Int8(bitPattern: $0) } + [Int8(0)]
        let dirPtr: UnsafeMutablePointer<Int8>? = templateBytes.withUnsafeMutableBufferPointer { buf in
            mkdtemp(buf.baseAddress)
        }
        guard let dirCStr = dirPtr else {
            throw HelperError.fifoFailed("mkdtemp: \(String(cString: strerror(errno)))")
        }
        let dir = String(cString: dirCStr)
        self.tmpDir = dir
        let cmd = "\(dir)/cmd.fifo"
        let resp = "\(dir)/resp.fifo"

        if mkfifo(cmd, 0o600) != 0 {
            let msg = String(cString: strerror(errno))
            cleanupPaths()
            throw HelperError.fifoFailed("mkfifo cmd: \(msg)")
        }
        if mkfifo(resp, 0o600) != 0 {
            let msg = String(cString: strerror(errno))
            unlink(cmd)
            cleanupPaths()
            throw HelperError.fifoFailed("mkfifo resp: \(msg)")
        }
        self.cmdPath = cmd
        self.respPath = resp

        // 2) Open resp as a NONBLOCK reader upfront. Proceeds with EAGAIN even before the writer (helper) exists.
        let respOpen = open(resp, O_RDONLY | O_NONBLOCK)
        if respOpen < 0 {
            let msg = String(cString: strerror(errno))
            cleanup()
            throw HelperError.fifoFailed("open resp: \(msg)")
        }
        self.respFD = respOpen

        // 3) Open cmd as RDWR. POSIX FIFO trick: RDWR means open/write won't block even without a reader.
        let cmdOpen = open(cmd, O_RDWR)
        if cmdOpen < 0 {
            let msg = String(cString: strerror(errno))
            cleanup()
            throw HelperError.fifoFailed("open cmd: \(msg)")
        }
        self.cmdFD = cmdOpen

        // 4) Launch the helper.
        do {
            if useSudo {
                try await launchSudoHelper(helperPath: helperPath, cmdFifo: cmd, respFifo: resp)
            } else {
                try launchPlainHelper(helperPath: helperPath, cmdFifo: cmd, respFifo: resp)
            }
        } catch {
            cleanup()
            throw error
        }
        helperLaunched = true

        // 5) Start the reader task.
        startReader()

        // 6) Ping round-trip to confirm the helper is alive.
        do {
            _ = try await send(HelperRequest(id: UUID().uuidString, op: .ping), timeout: 30.0)
        } catch {
            await stop()
            throw HelperError.userCancelled
        }
    }

    private func launchSudoHelper(helperPath: String, cmdFifo: String, respFifo: String) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // The shell command passed as the argument to `do shell script` inside AppleScript is
        // itself quoted, so double quotes within it must be escaped. AppleScript strings are also
        // delimited by double quotes, so `\"` is needed at both levels — but we avoid embedding
        // raw double quotes directly inside shellCommand.
        let safeHelper = helperPath.replacingOccurrences(of: "\"", with: "\\\"")
        let safeCmd = cmdFifo.replacingOccurrences(of: "\"", with: "\\\"")
        let safeResp = respFifo.replacingOccurrences(of: "\"", with: "\\\"")
        // Launch the helper in the background with stdin/stdout redirected to FIFOs. The & causes osascript to return immediately.
        let shellCommand = "\(safeHelper) <\(safeCmd) >\(safeResp) 2>/dev/null &"
        let script = "do shell script \"\(shellCommand)\" with administrator privileges"
        proc.arguments = ["-e", script]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            throw HelperError.spawnFailed("\(error)")
        }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            // User cancelled (-128) or authentication failed.
            throw HelperError.userCancelled
        }
    }

    private func launchPlainHelper(helperPath: String, cmdFifo: String, respFifo: String) throws {
        // Test-only: sh -c "uph <cmd >resp" child process. Because the parent (test) holds cmd open as RDWR,
        // the helper never sees stdin EOF and waits for round-trip requests.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        let safeHelper = helperPath.replacingOccurrences(of: "'", with: "'\\''")
        let safeCmd = cmdFifo.replacingOccurrences(of: "'", with: "'\\''")
        let safeResp = respFifo.replacingOccurrences(of: "'", with: "'\\''")
        proc.arguments = ["-c", "'\(safeHelper)' <'\(safeCmd)' >'\(safeResp)'"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            throw HelperError.spawnFailed("\(error)")
        }
        // Detached: do not wait for the helper to exit.
    }

    public func stop() async {
        readerTask?.cancel()
        readerTask = nil
        if cmdFD >= 0 { close(cmdFD); cmdFD = -1 }
        if respFD >= 0 { close(respFD); respFD = -1 }
        cleanup()
        helperLaunched = false
        let snapshot = pending
        pending.removeAll()
        for (_, cont) in snapshot {
            cont.resume(throwing: HelperError.notRunning)
        }
    }

    private func cleanupPaths() {
        if let dir = tmpDir { rmdir(dir) }
        cmdPath = nil; respPath = nil; tmpDir = nil
    }

    private func cleanup() {
        if let cmd = cmdPath { unlink(cmd) }
        if let resp = respPath { unlink(resp) }
        if let dir = tmpDir { rmdir(dir) }
        cmdPath = nil; respPath = nil; tmpDir = nil
    }

    public func send(_ req: HelperRequest, timeout: TimeInterval = 5.0) async throws -> HelperResponse {
        guard cmdFD >= 0 else { throw HelperError.notRunning }
        let line = try HelperCodec.encodeLine(req)
        let reqId = req.id
        let fd = cmdFD
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HelperResponse, Error>) in
            pending[reqId] = cont
            let bytes = [UInt8](line)
            let written = bytes.withUnsafeBufferPointer { buf -> Int in
                guard let base = buf.baseAddress else { return -1 }
                return Darwin.write(fd, base, buf.count)
            }
            if written < 0 {
                let msg = String(cString: strerror(errno))
                if let c = pending.removeValue(forKey: reqId) {
                    c.resume(throwing: HelperError.fifoFailed("write: \(msg)"))
                }
                return
            }
            let ns = UInt64(timeout * 1_000_000_000)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: ns)
                guard let self else { return }
                if let c = await self.pendingTake(id: reqId) {
                    c.resume(throwing: HelperError.timeout)
                }
            }
        }
    }

    private func pendingTake(id: String) -> CheckedContinuation<HelperResponse, Error>? {
        pending.removeValue(forKey: id)
    }

    private func startReader() {
        let fd = respFD
        readerTask = Task.detached(priority: .utility) { [weak self] in
            var buffer = Data()
            var readBuf = [UInt8](repeating: 0, count: 4096)
            while !Task.isCancelled {
                let n: Int = readBuf.withUnsafeMutableBufferPointer { buf -> Int in
                    guard let base = buf.baseAddress else { return -1 }
                    return Darwin.read(fd, base, buf.count)
                }
                if n > 0 {
                    buffer.append(readBuf, count: n)
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer.subdata(in: 0..<nl)
                        buffer.removeSubrange(0...nl)
                        if !lineData.isEmpty,
                           let resp = try? HelperCodec.decode(HelperResponse.self, from: lineData) {
                            await self?.deliver(resp)
                        }
                    }
                } else if n == 0 {
                    // EOF — the writer (helper) has closed.
                    break
                } else {
                    let e = errno
                    if e == EAGAIN || e == EWOULDBLOCK || e == EINTR {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        continue
                    }
                    break
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
