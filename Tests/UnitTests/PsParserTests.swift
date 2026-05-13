import XCTest
@testable import UsedPorts

final class PsParserTests: XCTestCase {
    let parser = PsParser()

    func test_lstart_singleDigitDay() {
        let d = parser.parseLstart("Mon May  5 10:23:14 2026")
        XCTAssertNotNil(d)
        let c = Calendar(identifier: .gregorian)
        let comp = c.dateComponents([.month, .day, .hour, .year], from: d!)
        XCTAssertEqual(comp.month, 5)
        XCTAssertEqual(comp.day, 5)
        XCTAssertEqual(comp.hour, 10)
        XCTAssertEqual(comp.year, 2026)
    }

    func test_lstart_doubleDigitDay() {
        let d = parser.parseLstart("Tue May 12 09:00:00 2026")
        XCTAssertNotNil(d)
    }

    func test_lstart_invalidReturnsNil() {
        XCTAssertNil(parser.parseLstart("not a date"))
    }

    func test_cwd_extractedFromFn() {
        let out = "p4821\nfcwd\nn/Users/name/Projects/my-app\n"
        XCTAssertEqual(parser.parseCwd(out), "/Users/name/Projects/my-app")
    }
}
