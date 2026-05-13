import XCTest
@testable import UsedPorts

final class HelperProtocolTests: XCTestCase {
    func test_roundtrip_scanResponse() throws {
        let entry = PortEntry(id: "x", pid: 1, processName: "p", user: "u",
                              proto: .tcp, localAddress: "*", port: 80, state: "LISTEN")
        let resp = HelperResponse(id: "abc", ok: true, entries: [entry])
        let data = try HelperCodec.encodeLine(resp)
        XCTAssertEqual(data.last, 0x0A)
        let parsed = try HelperCodec.decode(HelperResponse.self,
                                            from: data.dropLast())
        XCTAssertEqual(parsed, resp)
    }

    func test_roundtrip_killRequest() throws {
        let req = HelperRequest(id: "r1", op: .kill, pid: 4821, sig: 15)
        let data = try HelperCodec.encodeLine(req)
        let parsed = try HelperCodec.decode(HelperRequest.self,
                                            from: data.dropLast())
        XCTAssertEqual(parsed, req)
    }
}
