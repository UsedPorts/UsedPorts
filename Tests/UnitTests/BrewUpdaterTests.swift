import XCTest
@testable import UsedPorts

final class SeqRunner: @unchecked Sendable, CommandRunning {
    var responses: [(exit: Int32, out: String)] = []
    var calls: [(String, [String])] = []
    func run(_ path: String, args: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append((path, args))
        let r = responses.isEmpty ? (Int32(0), "") : responses.removeFirst()
        return CommandResult(exitCode: r.0, stdout: Data(r.1.utf8), stderr: Data())
    }
}

@MainActor
final class BrewUpdaterTests: XCTestCase {
    private static let autoKey = "BrewUpdater.autoCheckEnabled"
    private var savedAutoCheck: Any?

    override func setUp() {
        super.setUp()
        // Isolate from any persisted auto-check preference: with it left on,
        // BrewUpdater.init() fires a background checkNow that adds runner calls
        // and makes call-count assertions flaky. Saved/restored so running tests
        // doesn't clobber the developer's real setting.
        savedAutoCheck = UserDefaults.standard.object(forKey: Self.autoKey)
        UserDefaults.standard.removeObject(forKey: Self.autoKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedAutoCheck, forKey: Self.autoKey)
        super.tearDown()
    }

    func test_checkNow_setsUpdateAvailable() async {
        let runner = SeqRunner()
        runner.responses = [
            (0, ""),
            (0, #"{"formulae":[{"name":"usedports","installed_versions":["0.1.1"],"current_version":"0.2.0","pinned":false}],"casks":[]}"#)
        ]
        let updater = BrewUpdater(runner: runner, brewPath: "/opt/homebrew/bin/brew", formula: "usedports")
        await updater.checkNowAsync()
        XCTAssertTrue(updater.updateAvailable)
        XCTAssertEqual(updater.latestVersion, "0.2.0")
        XCTAssertNotNil(updater.lastCheckDate)
        XCTAssertFalse(updater.isChecking)
    }
    func test_checkNow_upToDate() async {
        let runner = SeqRunner()
        runner.responses = [(0, ""), (0, #"{"formulae":[],"casks":[]}"#)]
        let updater = BrewUpdater(runner: runner, brewPath: "/opt/homebrew/bin/brew", formula: "usedports")
        await updater.checkNowAsync()
        XCTAssertFalse(updater.updateAvailable)
        // When up to date, latest is reported as the current version so the UI
        // can always show a latest-version line.
        XCTAssertEqual(updater.latestVersion, updater.currentVersion)
    }
    func test_checkNow_sameAsRunningVersion_notOffered() async {
        // brew reports the brew-installed copy as outdated, but its "latest" equals
        // the actually-running build — no update should be offered.
        let runner = SeqRunner()
        let updater = BrewUpdater(runner: runner, brewPath: "/opt/homebrew/bin/brew", formula: "usedports")
        let cur = updater.currentVersion
        runner.responses = [
            (0, ""),
            (0, #"{"formulae":[{"name":"usedports/tap/usedports","installed_versions":["0.0.1"],"current_version":"\#(cur)"}],"casks":[]}"#)
        ]
        await updater.checkNowAsync()
        XCTAssertFalse(updater.updateAvailable)
        XCTAssertEqual(updater.latestVersion, cur)
    }
    func test_noBrew_disablesChecks() {
        let updater = BrewUpdater(runner: SeqRunner(), brewPath: nil, formula: "usedports")
        XCTAssertFalse(updater.canCheckNow)
        XCTAssertFalse(updater.isManagedByBrew)
    }
    func test_install_runsUpgradeAndRelaunches() async {
        let runner = SeqRunner()
        runner.responses = [(0, "")]
        var relaunched = false
        let updater = BrewUpdater(runner: runner, brewPath: "/opt/homebrew/bin/brew",
                                  formula: "usedports", relaunchHandler: { relaunched = true })
        await updater.installUpdateAsync()
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.0, "/opt/homebrew/bin/brew")
        XCTAssertEqual(runner.calls.first?.1, ["upgrade", "usedports"])
        XCTAssertTrue(relaunched)
        XCTAssertFalse(updater.isInstalling)
    }
    func test_install_failureDoesNotRelaunch() async {
        let runner = SeqRunner()
        runner.responses = [(1, "")]
        var relaunched = false
        let updater = BrewUpdater(runner: runner, brewPath: "/opt/homebrew/bin/brew",
                                  formula: "usedports", relaunchHandler: { relaunched = true })
        await updater.installUpdateAsync()
        XCTAssertFalse(relaunched)
        XCTAssertFalse(updater.isInstalling)
    }

    // Guards the actual production fix: recent Homebrew refuses to load formulae
    // from our third-party tap unless HOMEBREW_NO_REQUIRE_TAP_TRUST is set, which
    // a Finder/Homebrew-launched app does not inherit. The real runner must inject
    // it for every subprocess.
    func test_commandRunner_injectsTapTrustEnv() async throws {
        let res = try await CommandRunner().run("/usr/bin/env", args: [], timeout: 10)
        XCTAssertTrue(res.stdoutString.contains("HOMEBREW_NO_REQUIRE_TAP_TRUST=1"),
                      "env was:\n\(res.stdoutString)")
    }
}
