import XCTest
@testable import UsedPorts

final class BrewOutdatedTests: XCTestCase {
    func test_parse_updateAvailable() throws {
        let json = #"{"formulae":[{"name":"usedports","installed_versions":["0.1.1"],"current_version":"0.2.0","pinned":false}],"casks":[]}"#
        let result = BrewOutdated.parse(json.data(using: .utf8)!, formula: "usedports")
        XCTAssertEqual(result, .available(latest: "0.2.0"))
    }
    func test_parse_upToDate() throws {
        let json = #"{"formulae":[],"casks":[]}"#
        XCTAssertEqual(BrewOutdated.parse(json.data(using: .utf8)!, formula: "usedports"), .upToDate)
    }
    func test_parse_garbage_returnsUpToDate() throws {
        XCTAssertEqual(BrewOutdated.parse(Data("not json".utf8), formula: "usedports"), .upToDate)
    }

    // Task 7 tests
    func test_brewPath_prefersAppleSilicon() {
        XCTAssertEqual(BrewLocator.path(exists: { $0 == "/opt/homebrew/bin/brew" }), "/opt/homebrew/bin/brew")
    }
    func test_brewPath_fallsBackToIntel() {
        XCTAssertEqual(BrewLocator.path(exists: { $0 == "/usr/local/bin/brew" }), "/usr/local/bin/brew")
    }
    func test_brewPath_none() {
        XCTAssertNil(BrewLocator.path(exists: { _ in false }))
    }
}
