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

    func test_parse_tildeRange() {
        let s = NumberSpec.parse("1000~2000")
        XCTAssertEqual(s.ranges.count, 1)
        XCTAssertTrue(s.matches(1500))
        XCTAssertTrue(s.matches(1000))
        XCTAssertTrue(s.matches(2000))
        XCTAssertFalse(s.matches(2001))
        XCTAssertFalse(s.matches(999))
    }

    func test_parse_mixedDashTilde() {
        let s = NumberSpec.parse("100-200, 3000~4000, 5000")
        XCTAssertEqual(s.exact, [5000])
        XCTAssertEqual(s.ranges.count, 2)
        XCTAssertTrue(s.matches(150))
        XCTAssertTrue(s.matches(3500))
        XCTAssertTrue(s.matches(5000))
        XCTAssertFalse(s.matches(2500))
    }

    func test_parse_invalidTokensIgnored() {
        let s = NumberSpec.parse("abc, 3000, ,-, 100-50")
        XCTAssertEqual(s.exact, [3000])
        XCTAssertTrue(s.ranges.isEmpty)
    }

    func test_parse_plusSuffix_meansGreaterOrEqual() {
        let s = NumberSpec.parse("3000+")
        XCTAssertTrue(s.matches(3000))
        XCTAssertTrue(s.matches(99999))
        XCTAssertFalse(s.matches(2999))
    }

    func test_parse_openEndedRight_tilde() {
        let s = NumberSpec.parse("3000~")
        XCTAssertTrue(s.matches(3000))
        XCTAssertTrue(s.matches(50000))
        XCTAssertFalse(s.matches(2999))
    }

    func test_parse_openEndedRight_dash() {
        let s = NumberSpec.parse("3000-")
        XCTAssertTrue(s.matches(3000))
        XCTAssertTrue(s.matches(50000))
        XCTAssertFalse(s.matches(2999))
    }

    func test_parse_openEndedLeft_tilde() {
        let s = NumberSpec.parse("~3000")
        XCTAssertTrue(s.matches(0))
        XCTAssertTrue(s.matches(3000))
        XCTAssertFalse(s.matches(3001))
    }

    func test_parse_openEndedLeft_dash() {
        let s = NumberSpec.parse("-3000")
        XCTAssertTrue(s.matches(100))
        XCTAssertTrue(s.matches(3000))
        XCTAssertFalse(s.matches(3001))
    }

    func test_parse_mixedOperators() {
        let s = NumberSpec.parse("80, 1000~2000, 5000+, ~50")
        XCTAssertTrue(s.matches(25))      // ~50
        XCTAssertTrue(s.matches(80))      // exact
        XCTAssertTrue(s.matches(1500))    // 1000~2000
        XCTAssertTrue(s.matches(8000))    // 5000+
        XCTAssertFalse(s.matches(3000))
        XCTAssertFalse(s.matches(4999))
    }

    func test_emptyMatchesAll() {
        let s = NumberSpec()
        XCTAssertTrue(s.matches(1))
        XCTAssertTrue(s.matches(99999))
    }
}

final class TimeRangeSpecTests: XCTestCase {
    func test_anyMode_returnsNilRange() {
        let s = TimeRangeSpec(mode: .any)
        let (from, to) = s.toRange()
        XCTAssertNil(from)
        XCTAssertNil(to)
        XCTAssertTrue(s.isEmpty)
    }

    func test_last5m_returnsRecentFrom() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = TimeRangeSpec(mode: .last5m)
        let (from, to) = s.toRange(now: now)
        XCTAssertNotNil(from)
        XCTAssertNil(to)
        XCTAssertEqual(from!.timeIntervalSince1970, 999_700, accuracy: 0.001)
        XCTAssertFalse(s.isEmpty)
    }

    func test_last1h_returnsHourAgoFrom() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = TimeRangeSpec(mode: .last1h)
        let (from, _) = s.toRange(now: now)
        XCTAssertEqual(from!.timeIntervalSince1970, 996_400, accuracy: 0.001)
    }

    func test_customLast_min() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = TimeRangeSpec(mode: .customLast, lastN: 10, lastUnit: "min")
        let (from, _) = s.toRange(now: now)
        XCTAssertEqual(from!.timeIntervalSince1970, 999_400, accuracy: 0.001)
    }

    func test_customLast_hour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = TimeRangeSpec(mode: .customLast, lastN: 2, lastUnit: "hour")
        let (from, _) = s.toRange(now: now)
        XCTAssertEqual(from!.timeIntervalSince1970, 992_800, accuracy: 0.001)
    }

    func test_customLast_day() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let s = TimeRangeSpec(mode: .customLast, lastN: 1, lastUnit: "day")
        let (from, _) = s.toRange(now: now)
        XCTAssertEqual(from!.timeIntervalSince1970, 913_600, accuracy: 0.001)
    }

    func test_customLast_invalidNIsEmpty() {
        let s = TimeRangeSpec(mode: .customLast, lastN: 0, lastUnit: "min")
        XCTAssertTrue(s.isEmpty)
        let (from, to) = s.toRange()
        XCTAssertNil(from)
        XCTAssertNil(to)
    }

    func test_customFixed_emptyWhenNoDates() {
        let s = TimeRangeSpec(mode: .customFixed)
        XCTAssertTrue(s.isEmpty)
    }
}
