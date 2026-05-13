import XCTest
@testable import UsedPorts

/// Calls real lsof, so this only runs on macOS.
final class NcRoundtripTests: XCTestCase {

    func test_listeningPort_isVisibleAndKillable() async throws {
        let port = UInt16.random(in: 49152...60000)
        let nc = Process()
        nc.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        nc.arguments = ["-l", "\(port)"]
        // Discard nc's output.
        nc.standardOutput = Pipe()
        nc.standardError = Pipe()
        try nc.run()
        defer { if nc.isRunning { nc.terminate() } }

        // Give nc a moment to open the LISTEN socket. Retry because it can be slow depending on environment.
        var found: PortEntry?
        let scanner = PortScanner()
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 300_000_000)
            let entries = try await scanner.scanOnce()
            if let hit = entries.first(where: { $0.port == port }) {
                found = hit
                break
            }
        }
        XCTAssertNotNil(found, "lsof did not find nc LISTEN on port \(port)")
        XCTAssertEqual(found?.proto, .tcp)

        guard let pid = found?.pid else { return }
        let killer = KillSupervisor()
        let outcome = await killer.kill(pid: pid, signal: .term)
        XCTAssertEqual(outcome, .terminated)

        // lsof results may take a moment to reflect the kill.
        var sawAfter: PortEntry? = nil
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 300_000_000)
            let after = try await scanner.scanOnce()
            sawAfter = after.first { $0.port == port }
            if sawAfter == nil { break }
        }
        XCTAssertNil(sawAfter, "Port \(port) still visible after kill")
    }
}
