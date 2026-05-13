import XCTest
@testable import UsedPorts

final class ElevatedHelperTests: XCTestCase {
    /// Locates the uph binary in the build products.
    private func findUphBinary() -> String? {
        let fm = FileManager.default

        // 1) Directly from environment variables
        let env = ProcessInfo.processInfo.environment
        for key in ["BUILT_PRODUCTS_DIR", "BUILD_DIR", "TARGET_BUILD_DIR"] {
            if let dd = env[key] {
                let p = "\(dd)/uph"
                if fm.fileExists(atPath: p) { return p }
            }
        }

        // 2) Built alongside the test bundle (xcodebuild)
        let bundle = Bundle(for: ElevatedHelperTests.self)
        let bundleDir = bundle.bundleURL.deletingLastPathComponent()
        let candidate = bundleDir.appendingPathComponent("uph").path
        if fm.fileExists(atPath: candidate) { return candidate }

        // 3) Copied into the host app's Resources
        let resourceCandidate = bundleDir
            .appendingPathComponent("UsedPorts.app/Contents/Resources/uph").path
        if fm.fileExists(atPath: resourceCandidate) { return resourceCandidate }

        return nil
    }

    func test_ping_roundtrip_via_fifo() async throws {
        guard let uph = findUphBinary() else {
            throw XCTSkip("uph binary not found in build products")
        }
        let helper = ElevatedHelper()
        try await helper.startForTesting(helperPath: uph)
        let resp = try await helper.send(
            HelperRequest(id: "ping-1", op: .ping),
            timeout: 10.0
        )
        XCTAssertTrue(resp.ok)
        XCTAssertEqual(resp.id, "ping-1")
        await helper.stop()
    }

    func test_scan_returns_entries() async throws {
        guard let uph = findUphBinary() else {
            throw XCTSkip("uph binary not found in build products")
        }
        let helper = ElevatedHelper()
        try await helper.startForTesting(helperPath: uph)
        let resp = try await helper.send(
            HelperRequest(id: "scan-1", op: .scan),
            timeout: 15.0
        )
        XCTAssertTrue(resp.ok, "scan failed: \(resp.message ?? "nil")")
        XCTAssertEqual(resp.id, "scan-1")
        XCTAssertNotNil(resp.entries)
        await helper.stop()
    }
}
