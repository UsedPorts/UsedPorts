import XCTest
@testable import UsedPorts

final class CommandRunnerTests: XCTestCase {
    let runner = CommandRunner()

    func test_echo_returnsStdout() async throws {
        let r = try await runner.run("/bin/echo", args: ["hello"], timeout: 2)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func test_false_returnsNonZeroExit() async throws {
        let r = try await runner.run("/usr/bin/false", args: [], timeout: 2)
        XCTAssertNotEqual(r.exitCode, 0)
    }

    func test_stderr_captured() async throws {
        let r = try await runner.run("/bin/sh", args: ["-c", "echo bad >&2"], timeout: 2)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stderrString.trimmingCharacters(in: .whitespacesAndNewlines), "bad")
    }

    func test_forcesCLocale() async throws {
        let r = try await runner.run("/bin/sh", args: ["-c", "echo $LC_ALL"], timeout: 2)
        XCTAssertEqual(r.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines), "C")
    }

    func test_psLstart_isEnglishParseable() async throws {
        // Regression: Finder/Homebrew launches inherit a localized session
        // locale, which made `ps -o lstart=` emit non-English dates the parser
        // dropped. Forcing LC_ALL=C keeps the output parseable.
        let r = try await runner.run("/bin/ps", args: ["-o", "lstart=", "-p", "\(getpid())"], timeout: 2)
        XCTAssertNotNil(PsParser().parseLstart(r.stdoutString))
    }

    func test_timeout_throws() async {
        do {
            _ = try await runner.run("/bin/sleep", args: ["5"], timeout: 0.3)
            XCTFail("expected timeout")
        } catch CommandError.timedOut {
            // OK
        } catch {
            XCTFail("expected timedOut, got \(error)")
        }
    }
}
