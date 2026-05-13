import XCTest
@testable import UsedPorts

final class ScriptedRunner: @unchecked Sendable, CommandRunning {
    /// (path, args matcher) → stdout
    var responses: [((String, [String]) -> Bool, String)] = []
    func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        for (matcher, body) in responses where matcher(path, args) {
            return CommandResult(exitCode: 0, stdout: body.data(using: .utf8) ?? Data(), stderr: Data())
        }
        return CommandResult(exitCode: 1, stdout: Data(), stderr: Data())
    }
}

final class ProcessAugmenterTests: XCTestCase {
    func test_augment_fillsAllFields() async {
        let runner = ScriptedRunner()
        runner.responses = [
            ({ p, a in p == "/bin/ps" && a.contains("comm=") }, "/opt/homebrew/bin/node\n"),
            ({ p, a in p == "/bin/ps" && a.contains("lstart=") }, "Mon May 12 10:23:14 2026\n"),
            ({ p, _ in p == "/usr/sbin/lsof" }, "p4821\nfcwd\nn/Users/name/Projects/my-app\n"),
        ]
        let augmenter = ProcessAugmenter(runner: runner)
        let base = PortEntry(id: "x", pid: 4821, processName: "node", user: "name",
                              proto: .tcp, localAddress: "127.0.0.1", port: 3000, state: "LISTEN")
        let out = await augmenter.augment(base)
        XCTAssertEqual(out.executablePath, "/opt/homebrew/bin/node")
        XCTAssertNotNil(out.startTime)
        XCTAssertEqual(out.cwd, "/Users/name/Projects/my-app")
    }

    func test_augment_handlesMissingExec() async {
        let runner = ScriptedRunner()
        let augmenter = ProcessAugmenter(runner: runner)
        let base = PortEntry(id: "x", pid: 99999, processName: "?", user: "?",
                              proto: .tcp, localAddress: "*", port: 1, state: nil)
        let out = await augmenter.augment(base)
        XCTAssertNil(out.executablePath)
        XCTAssertNil(out.cwd)
    }
}
