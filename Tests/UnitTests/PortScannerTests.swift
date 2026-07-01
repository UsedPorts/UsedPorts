import XCTest
@testable import UsedPorts

final class StubRunner: @unchecked Sendable, CommandRunning {
    var nextStdout: String = ""
    var nextExit: Int32 = 0
    var capturedCalls: [(String, [String])] = []
    func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        capturedCalls.append((path, args))
        return CommandResult(
            exitCode: nextExit,
            stdout: nextStdout.data(using: .utf8) ?? Data(),
            stderr: Data()
        )
    }
}

final class PortScannerTests: XCTestCase {
    func test_scanOnce_callsLsofWithExpectedArgs() async throws {
        let runner = StubRunner()
        runner.nextStdout = ""
        let scanner = PortScanner(runner: runner)
        _ = try await scanner.scanOnce()
        let (path, args) = runner.capturedCalls.first!
        XCTAssertEqual(path, "/usr/sbin/lsof")
        XCTAssertEqual(args, ["-nP", "-iTCP", "-iUDP", "-F", "pcuLnPTt"])
    }

    func test_scanOnce_parsesEntries() async throws {
        let runner = StubRunner()
        runner.nextStdout = """
        p4821
        cnode
        uname
        f23
        PTCP
        n127.0.0.1:3000
        TST=LISTEN
        """
        let scanner = PortScanner(runner: runner)
        let entries = try await scanner.scanOnce()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].port, 3000)
    }

    func test_startPolling_immediateFirstScanFalse_defersScan() async {
        let runner = StubRunner()
        let scanner = PortScanner(runner: runner)
        _ = await scanner.startPolling(intervalSeconds: 10, immediateFirstScan: false)
        try? await Task.sleep(nanoseconds: 200_000_000)   // 0.2s « 10s interval
        let calls = runner.capturedCalls.count
        await scanner.stopPolling()
        XCTAssertEqual(calls, 0, "no scan should run before the first interval when deferred")
    }

    func test_startPolling_immediateFirstScanTrue_scansRightAway() async {
        let runner = StubRunner()
        let scanner = PortScanner(runner: runner)
        _ = await scanner.startPolling(intervalSeconds: 10, immediateFirstScan: true)
        try? await Task.sleep(nanoseconds: 200_000_000)
        let calls = runner.capturedCalls.count
        await scanner.stopPolling()
        XCTAssertGreaterThanOrEqual(calls, 1, "immediate scan should run right away")
    }

    func test_scanOnce_elevatedTakesPrecedence() async throws {
        let runner = StubRunner()
        let scanner = PortScanner(runner: runner)
        let stubbed = [PortEntry(id: "x", pid: 1, processName: "init", user: "root",
                                  proto: .tcp, localAddress: "*", port: 1, state: "LISTEN")]
        await scanner.setElevatedScanner { stubbed }
        let entries = try await scanner.scanOnce()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(runner.capturedCalls.count, 0, "elevated path skips runner")
    }
}
