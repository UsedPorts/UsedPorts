import Foundation

public struct CommandResult {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data
    public var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
    public var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }
}

public enum CommandError: Error {
    case timedOut
    case launchFailed(String)
}

public protocol CommandRunning {
    func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult
}

public struct CommandRunner: CommandRunning {
    public init() {}

    public func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        // Force the C locale so tools like `ps -o lstart=` emit a stable,
        // English-formatted timestamp regardless of how the app was launched.
        // Finder/Homebrew launches inherit the GUI session locale (e.g.
        // ko_KR.UTF-8), which our parsers can't read; Xcode launches happen to
        // inherit a neutral locale, which is why this only broke in release.
        // LC_ALL overrides LANG/LC_TIME.
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        // Our own tap (usedports/tap) is a third-party tap, and recent Homebrew
        // refuses to load formulae from an untrusted tap — `brew outdated` then
        // errors instead of emitting JSON, so the update check silently reports
        // "up to date". A Finder/Homebrew launch doesn't inherit the shell's
        // HOMEBREW_NO_REQUIRE_TAP_TRUST, so set it here for every brew call.
        // Inert for non-brew commands (e.g. `ps`).
        env["HOMEBREW_NO_REQUIRE_TAP_TRUST"] = "1"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed("\(error)")
        }

        let outData = Locked<Data>(value: Data())
        let errData = Locked<Data>(value: Data())

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            else { outData.mutate { $0.append(chunk) } }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            else { errData.mutate { $0.append(chunk) } }
        }

        let resumed = Locked<Bool>(value: false)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CommandResult, Error>) in
                let deadline = DispatchTime.now() + timeout
                let timeoutItem = DispatchWorkItem {
                    var shouldResume = false
                    resumed.mutate { if !$0 { $0 = true; shouldResume = true } }
                    if shouldResume {
                        if process.isRunning { process.terminate() }
                        cont.resume(throwing: CommandError.timedOut)
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: deadline, execute: timeoutItem)

                process.terminationHandler = { proc in
                    timeoutItem.cancel()
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    let restOut = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let restErr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    outData.mutate { $0.append(restOut) }
                    errData.mutate { $0.append(restErr) }
                    var shouldResume = false
                    resumed.mutate { if !$0 { $0 = true; shouldResume = true } }
                    if shouldResume {
                        cont.resume(returning: CommandResult(
                            exitCode: proc.terminationStatus,
                            stdout: outData.value,
                            stderr: errData.value
                        ))
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

final class Locked<T> {
    private var _value: T
    private let lock = NSLock()
    init(value: T) { _value = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return _value }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&_value); lock.unlock() }
}
