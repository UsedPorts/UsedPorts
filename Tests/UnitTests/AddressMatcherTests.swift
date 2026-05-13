import XCTest
@testable import UsedPorts

final class AddressMatcherTests: XCTestCase {
    func test_emptyQueryMatchesAll() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "127.0.0.1", query: ""))
        XCTAssertTrue(AddressMatcher.matches(localAddress: "*", query: "  "))
    }

    func test_exactIPv4() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "127.0.0.1", query: "127.0.0.1"))
        XCTAssertFalse(AddressMatcher.matches(localAddress: "127.0.0.1", query: "127.0.0.2"))
    }

    func test_cidrIPv4() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "192.168.1.5", query: "192.168.1.0/24"))
        XCTAssertFalse(AddressMatcher.matches(localAddress: "192.168.2.5", query: "192.168.1.0/24"))
        XCTAssertTrue(AddressMatcher.matches(localAddress: "10.0.0.1", query: "10.0.0.0/8"))
    }

    func test_cidrIPv4_zeroPrefixMatchesAll() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "8.8.8.8", query: "0.0.0.0/0"))
        XCTAssertTrue(AddressMatcher.matches(localAddress: "*", query: "0.0.0.0/0"))
    }

    func test_wildcardEntryIsTreatedAsZero() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "*", query: "0.0.0.0"))
        // Wildcard listening is not a substring match for a specific IP
        XCTAssertFalse(AddressMatcher.matches(localAddress: "*", query: "127.0.0.1"))
    }

    func test_ipv6_brackets_stripped() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "[::1]", query: "::1"))
        XCTAssertTrue(AddressMatcher.matches(localAddress: "[fe80::1]", query: "fe80::/16"))
    }

    func test_commaSeparated_or() {
        XCTAssertTrue(AddressMatcher.matches(localAddress: "192.168.1.5", query: "10.0.0.0/8, 192.168.1.0/24"))
        XCTAssertFalse(AddressMatcher.matches(localAddress: "172.16.0.1", query: "10.0.0.0/8, 192.168.1.0/24"))
    }

    func test_substringFallback() {
        // Plain text that is not a CIDR/IP falls back to substring contains on the raw address
        XCTAssertTrue(AddressMatcher.matches(localAddress: "127.0.0.1", query: "127"))
        XCTAssertTrue(AddressMatcher.matches(localAddress: "[::1]", query: "::"))
    }
}
