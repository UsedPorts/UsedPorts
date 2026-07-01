import XCTest
import AppKit
@testable import UsedPorts

private final class FakeResolver: RunningAppIconResolving {
    var calls: [pid_t] = []
    var icons: [pid_t: NSImage?] = [:]
    func icon(forPID pid: pid_t) -> NSImage? {
        calls.append(pid)
        return icons[pid] ?? nil
    }
}

@MainActor
final class ProcessIconProviderTests: XCTestCase {
    func test_cacheHit_resolvesOncePerPID() {
        let fake = FakeResolver()
        fake.icons[42] = NSImage()
        let provider = ProcessIconProvider(resolver: fake)

        XCTAssertNotNil(provider.icon(forPID: 42))
        XCTAssertNotNil(provider.icon(forPID: 42))
        XCTAssertNotNil(provider.icon(forPID: 42))

        XCTAssertEqual(fake.calls, [42], "resolver should be hit exactly once per pid")
    }

    func test_noAppIcon_fallsBackToGenericIcon_andCaches() {
        let fake = FakeResolver()           // pid 7 has no app icon (CLI process)
        let provider = ProcessIconProvider(resolver: fake)

        // No app icon → generic fallback (not nil) so the icon column isn't blank.
        XCTAssertTrue(provider.icon(forPID: 7) === ProcessIconProvider.genericIcon)
        XCTAssertTrue(provider.icon(forPID: 7) === ProcessIconProvider.genericIcon)

        XCTAssertEqual(fake.calls, [7], "nil app-icon must be cached so CLI pids aren't re-resolved")
    }

    func test_prune_dropsDeadPIDs_keepsSurvivors() {
        let fake = FakeResolver()
        fake.icons[1] = NSImage()
        fake.icons[2] = NSImage()
        let provider = ProcessIconProvider(resolver: fake)
        _ = provider.icon(forPID: 1)
        _ = provider.icon(forPID: 2)
        XCTAssertEqual(provider.cachedCount, 2)

        provider.prune(livePIDs: [2])
        XCTAssertEqual(provider.cachedCount, 1)

        // pid 2 survived → still a cache hit (no new resolver call)
        _ = provider.icon(forPID: 2)
        XCTAssertEqual(fake.calls, [1, 2], "survivor stays cached after prune")

        // pid 1 was pruned → re-resolved on next lookup
        _ = provider.icon(forPID: 1)
        XCTAssertEqual(fake.calls, [1, 2, 1], "pruned pid is resolved afresh")
    }
}
