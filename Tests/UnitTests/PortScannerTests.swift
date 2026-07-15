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
        // Poll up to ~2s (« 10s interval) so a busy machine doesn't flake the assertion.
        var calls = 0
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            calls = runner.capturedCalls.count
            if calls >= 1 { break }
        }
        await scanner.stopPolling()
        XCTAssertGreaterThanOrEqual(calls, 1, "immediate scan should run promptly")
    }

    // Restarting the stream cancels the previous poll task mid-scan; CommandRunner
    // then returns lsof's *partial* output. That truncated batch (ports missing) must
    // be dropped, not yielded into the new stream — it flaps the UI and fires
    // spurious pinned-port "closed" notifications.
    func test_streamRestart_dropsCancelledPartialScan() async {
        final class SlowThenFastRunner: @unchecked Sendable, CommandRunning {
            var callCount = 0
            func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
                callCount += 1
                if callCount == 1 {
                    // Emulate CommandRunner under cancellation: lsof is terminated and
                    // the output collected so far (here: nothing) is returned as-is.
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    return CommandResult(exitCode: 15, stdout: Data(), stderr: Data())
                }
                let full = "p4821\ncnode\nuname\nf23\nPTCP\nn127.0.0.1:3000\nTST=LISTEN\n"
                return CommandResult(exitCode: 0, stdout: Data(full.utf8), stderr: Data())
            }
        }
        let runner = SlowThenFastRunner()
        let scanner = PortScanner(runner: runner)
        _ = await scanner.startPolling(intervalSeconds: 10, immediateFirstScan: true)
        try? await Task.sleep(nanoseconds: 100_000_000)   // let scan 1 get in-flight
        let stream = await scanner.startPolling(intervalSeconds: 10, immediateFirstScan: true)
        var first: [PortEntry]?
        for await batch in stream { first = batch; break }
        await scanner.stopPolling()
        XCTAssertEqual(first?.map(\.port), [3000],
                       "cancelled scan's partial batch must not leak into the new stream")
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
