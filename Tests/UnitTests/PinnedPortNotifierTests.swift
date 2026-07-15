import XCTest
@testable import UsedPorts

final class PinnedPortNotifierTests: XCTestCase {
    private typealias Event = PinnedPortNotifier.PortEvent

    // Same isolation as BrewUpdaterTests: AppSettings persists to the test host's real
    // UserDefaults, so save/restore the keys this test mutates.
    private static let mutatedKeys = [
        "settings.pinnedPortNotifications",
        "settings.pinnedPortNotificationTrigger",
        "settings.pinnedPorts",
    ]
    private var savedValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in Self.mutatedKeys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.mutatedKeys {
            if let value = savedValues[key], let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testOpenedEvent() {
        let events = PinnedPortNotifier.events(
            previous: [80], current: [80, 3000], pinned: [3000], trigger: .both)
        XCTAssertEqual(events, [Event(port: 3000, kind: .opened)])
    }

    func testClosedEvent() {
        let events = PinnedPortNotifier.events(
            previous: [80, 3000], current: [80], pinned: [3000], trigger: .both)
        XCTAssertEqual(events, [Event(port: 3000, kind: .closed)])
    }

    func testUnpinnedPortsAreIgnored() {
        let events = PinnedPortNotifier.events(
            previous: [80], current: [8080], pinned: [3000], trigger: .both)
        XCTAssertTrue(events.isEmpty)
    }

    func testTriggerOpenedFiltersClosedEvents() {
        let events = PinnedPortNotifier.events(
            previous: [3000], current: [3001], pinned: [3000, 3001], trigger: .opened)
        XCTAssertEqual(events, [Event(port: 3001, kind: .opened)])
    }

    func testTriggerClosedFiltersOpenedEvents() {
        let events = PinnedPortNotifier.events(
            previous: [3000], current: [3001], pinned: [3000, 3001], trigger: .closed)
        XCTAssertEqual(events, [Event(port: 3000, kind: .closed)])
    }

    func testStablePortOrdering() {
        let events = PinnedPortNotifier.events(
            previous: [], current: [3002, 3000, 3001], pinned: [3000, 3001, 3002], trigger: .both)
        XCTAssertEqual(events.map(\.port), [3000, 3001, 3002])
    }

    // Pinning a port that is already open must not fabricate an "opened" event:
    // the diff is over open-port snapshots, so an unchanged port never flips.
    func testPinningAlreadyOpenPortProducesNoEvent() {
        let events = PinnedPortNotifier.events(
            previous: [3000], current: [3000], pinned: [3000], trigger: .both)
        XCTAssertTrue(events.isEmpty)
    }

    // Copy assertions are locale-agnostic (the test host may run in en or ko):
    // check the interpolated data, not the localized sentence.
    func testMessageIsPortCentricWithProcessInBody() {
        let info = PinnedPortNotifier.PortProcessInfo(
            name: "workerd", pid: 4821, address: "127.0.0.1:8787")
        let (title, body) = PinnedPortNotifier.message(
            for: Event(port: 8787, kind: .opened), info: info)
        XCTAssertTrue(title.contains("8787"), "port must not be locale-grouped (8,787)")
        XCTAssertFalse(title.contains("8,787"))
        XCTAssertFalse(title.contains("workerd"), "process lives in the body, not the title")
        XCTAssertEqual(body?.contains("workerd"), true)
        XCTAssertEqual(body?.contains("'workerd'"), false, "process name is not quoted")
        XCTAssertEqual(body?.contains("127.0.0.1:8787"), true)
        XCTAssertEqual(body?.contains("4821"), true)
    }

    func testMessageBodyOmitsQuotesForEmptyProcessName() {
        let info = PinnedPortNotifier.PortProcessInfo(name: "", pid: 4821, address: "*:8787")
        let (_, body) = PinnedPortNotifier.message(
            for: Event(port: 8787, kind: .closed), info: info)
        XCTAssertEqual(body?.contains("''"), false)
        XCTAssertEqual(body?.contains("*:8787"), true)
        XCTAssertEqual(body?.contains("4821"), true)
    }

    func testMessageFallsBackWithoutProcessInfo() {
        let (title, body) = PinnedPortNotifier.message(
            for: Event(port: 8787, kind: .closed), info: nil)
        XCTAssertTrue(title.contains("8787"))
        XCTAssertFalse(title.contains("8,787"))
        XCTAssertNil(body)
    }

    @MainActor
    func testIngestBaselineAndTransition() {
        let settings = AppSettings()
        settings.pinnedPortNotificationsEnabled = true
        settings.pinnedPorts = [3000]
        let notifier = PinnedPortNotifier(settings: settings)

        func entry(port: UInt16, name: String) -> PortEntry {
            PortEntry(id: "\(name)-\(port)", pid: 1, processName: name, user: "u",
                      proto: .tcp, localAddress: "127.0.0.1:\(port)", port: port, state: "LISTEN")
        }

        // First batch is baseline only — must not crash or notify (delivery goes through
        // UNUserNotificationCenter, which is a no-op without granted permission in tests).
        notifier.ingest([entry(port: 3000, name: "node")])
        notifier.ingest([])          // closed transition path
        notifier.ingest([entry(port: 3000, name: "node")])  // opened transition path
    }
}
