import XCTest
@testable import UsedPorts

final class NumberSpecTests: XCTestCase {
    func test_parse_singleValue() {
        let s = NumberSpec.parse("3000")
        XCTAssertEqual(s.exact, [3000])
        XCTAssertTrue(s.ranges.isEmpty)
        XCTAssertTrue(s.matches(3000))
        XCTAssertFalse(s.matches(3001))
    }

    func test_parse_range() {
        let s = NumberSpec.parse("1000-2000")
        XCTAssertEqual(s.ranges.count, 1)
        XCTAssertTrue(s.matches(1500))
        XCTAssertFalse(s.matches(2001))
    }

    func test_parse_mixedList() {
        let s = NumberSpec.parse("3000,5432, 8080-8090")
        XCTAssertEqual(s.exact, [3000, 5432])
        XCTAssertTrue(s.matches(8085))
        XCTAssertTrue(s.matches(3000))
        XCTAssertFalse(s.matches(9000))
    }

    func test_parse_invalidTokensIgnored() {
        let s = NumberSpec.parse("abc, 3000, ,-, 100-50")
        XCTAssertEqual(s.exact, [3000])
        XCTAssertTrue(s.ranges.isEmpty)
    }

    func test_emptyMatchesAll() {
        let s = NumberSpec()
        XCTAssertTrue(s.matches(1))
        XCTAssertTrue(s.matches(99999))
    }
}
