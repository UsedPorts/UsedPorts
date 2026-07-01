import XCTest
@testable import UsedPorts

final class ScriptedRunner: @unchecked Sendable, CommandRunning {
    /// (path, args matcher) → stdout
    var responses: [((String, [String]) -> Bool, String)] = []
    var calls: [(String, [String])] = []
    func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append((path, args))
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
            ({ p, a in p == "/bin/ps" && a.contains("pid=,comm=") }, "4821 /opt/homebrew/bin/node\n"),
            ({ p, a in p == "/bin/ps" && a.contains("pid=,lstart=") }, "4821 Mon May 12 10:23:14 2026\n"),
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

    func test_augmentPids_batchFetchesStartTimesOnly() async {
        let runner = ScriptedRunner()
        runner.responses = [
            ({ p, a in p == "/bin/ps" && a.contains("pid=,lstart=") },
             "4821 Mon May 12 10:23:14 2026\n559 Tue May 13 09:00:00 2026\n"),
        ]
        let augmenter = ProcessAugmenter(runner: runner)
        let out = await augmenter.augment(pids: [4821, 559])
        XCTAssertNotNil(out[4821]?.startTime)
        XCTAssertNotNil(out[559]?.startTime)
        // Bulk augmentation must NOT fetch exec path or cwd (list has no such columns;
        // batching lsof cwd is slow). Only the ps lstart call should run.
        XCTAssertNil(out[4821]?.executablePath)
        XCTAssertNil(out[4821]?.cwd)
        XCTAssertEqual(runner.calls.count, 1, "bulk augment should spawn exactly one subprocess")
        XCTAssertEqual(runner.calls.first?.0, "/bin/ps")
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
