import XCTest
@testable import UsedPorts

final class BrewOutdatedTests: XCTestCase {
    func test_stableVersion_fromBrewInfo() {
        let json = #"{"formulae":[{"name":"usedports","full_name":"usedports/tap/usedports","versions":{"stable":"0.1.3","head":null,"bottle":true},"installed":[{"version":"0.1.3"}]}],"casks":[]}"#
        XCTAssertEqual(BrewInfo.stableVersion(Data(json.utf8)), "0.1.3")
    }
    func test_stableVersion_noFormula_isNil() {
        XCTAssertNil(BrewInfo.stableVersion(Data(#"{"formulae":[],"casks":[]}"#.utf8)))
    }
    func test_stableVersion_garbage_isNil() {
        XCTAssertNil(BrewInfo.stableVersion(Data("not json".utf8)))
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
