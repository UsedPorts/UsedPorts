import XCTest
@testable import UsedPorts

final class LsofParserTests: XCTestCase {
    let parser = LsofParser()

    private func loadFixture(_ name: String) -> String {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "txt")
        guard let url else {
            XCTFail("fixture \(name).txt not found in bundle")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func test_basicFixture_extractsAllEntries() {
        let entries = parser.parse(loadFixture("lsof-basic"))
        XCTAssertEqual(entries.count, 4)
    }

    func test_basic_postgresListen() {
        let entries = parser.parse(loadFixture("lsof-basic"))
        let postgres = entries.first { $0.processName == "postgres" }!
        XCTAssertEqual(postgres.pid, 318)
        XCTAssertEqual(postgres.user, "_postgres")
        XCTAssertEqual(postgres.proto, .tcp)
        XCTAssertEqual(postgres.localAddress, "*")
        XCTAssertEqual(postgres.port, 5432)
        XCTAssertEqual(postgres.state, "LISTEN")
    }

    func test_basic_nodeHasTwoEntries() {
        let entries = parser.parse(loadFixture("lsof-basic"))
        let nodeOnes = entries.filter { $0.processName == "node" }
        XCTAssertEqual(nodeOnes.count, 2)
        let states = Set(nodeOnes.compactMap { $0.state })
        XCTAssertEqual(states, ["LISTEN", "ESTABLISHED"])
    }

    func test_udp_hasNoState() {
        let entries = parser.parse(loadFixture("lsof-basic"))
        let mdns = entries.first { $0.processName == "mDNSResponder" }!
        XCTAssertEqual(mdns.proto, .udp)
        XCTAssertNil(mdns.state)
        XCTAssertEqual(mdns.port, 5353)
    }

    func test_ipv6_parsesAddressAndPort() {
        let entries = parser.parse(loadFixture("lsof-ipv6"))
        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.localAddress, "[::1]")
        XCTAssertEqual(e.port, 8443)
        XCTAssertEqual(e.ipFamily, .v6)
    }

    func test_basic_ipFamilyIsIPv4() {
        let entries = parser.parse(loadFixture("lsof-basic"))
        for e in entries {
            XCTAssertEqual(e.ipFamily, .v4, "expected IPv4 for \(e.processName) port \(e.port)")
        }
    }

    func test_uniqueIdsAcrossFds() {
        let entries = parser.parse(loadFixture("lsof-basic"))
        let ids = Set(entries.map { $0.id })
        XCTAssertEqual(ids.count, entries.count)
    }
}
