import XCTest
import Combine
@testable import UsedPorts

/// Fills augment fields synchronously, no gating.
final class FillingAugmenter: ProcessAugmenting, @unchecked Sendable {
    func augment(pids: [Int32]) async -> [Int32: ProcessAugmentation] {
        var out: [Int32: ProcessAugmentation] = [:]
        for pid in pids {
            out[pid] = ProcessAugmentation(executablePath: "/mock/exec", cwd: "/mock/cwd")
        }
        return out
    }
}

/// Counts augment calls and gates the very first call until released, so a test
/// can observe whether a second augmentation pass is (incorrectly) started while
/// the first is still in flight.
final class GatedAugmenter: ProcessAugmenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var cont: CheckedContinuation<Void, Never>?
    let firstCallReached = XCTestExpectation(description: "augment first call reached")

    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }

    func augment(pids: [Int32]) async -> [Int32: ProcessAugmentation] {
        lock.lock(); _count += 1; let n = _count; lock.unlock()
        if n == 1 {
            firstCallReached.fulfill()
            await withCheckedContinuation { c in
                lock.lock(); cont = c; lock.unlock()
            }
        }
        var out: [Int32: ProcessAugmentation] = [:]
        for pid in pids { out[pid] = ProcessAugmentation(executablePath: "/mock/\(pid)") }
        return out
    }

    func release() {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume()
    }
}

final class PortListViewModelTests: XCTestCase {
    /// Single-entry lsof -F fixture (pid 4821, port 3000).
    static let oneEntryLsof = """
    p4821
    cnode
    uname
    f23
    PTCP
    n127.0.0.1:3000
    TST=LISTEN
    """

    /// Same PID (4821), different port (3001) — a changed batch that still targets
    /// the same PID, used to exercise the in-flight augmentation guard.
    static let oneEntryLsofAltPort = """
    p4821
    cnode
    uname
    f23
    PTCP
    n127.0.0.1:3001
    TST=LISTEN
    """

    func makeEntries() -> [PortEntry] {
        [
            PortEntry(id: "a", pid: 100, processName: "node", user: "name",
                      proto: .tcp, localAddress: "127.0.0.1", port: 3000, state: "LISTEN"),
            PortEntry(id: "b", pid: 200, processName: "postgres", user: "_postgres",
                      proto: .tcp, localAddress: "*", port: 5432, state: "LISTEN"),
            PortEntry(id: "c", pid: 300, processName: "Chrome", user: "name",
                      proto: .udp, localAddress: "*", port: 5353, state: nil),
        ]
    }

    func test_sortByPortAsc() {
        let entries = makeEntries()
        let sorted = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: FilterState(),
            to: entries)
        XCTAssertEqual(sorted.map(\.port), [3000, 5353, 5432])
    }

    func test_sortByProcessDesc() {
        let sorted = PortListViewModel.apply(
            sort: SortSpec(column: .process, dir: .desc),
            filter: FilterState(),
            to: makeEntries())
        XCTAssertEqual(sorted.map(\.processName), ["postgres", "node", "Chrome"])
    }

    func test_filterByProto_udpOnly() {
        var f = FilterState()
        f.byColumn[.proto] = .multiSelect(["UDP"])
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.processName), ["Chrome"])
    }

    func test_filterByPortRange() {
        var f = FilterState()
        f.byColumn[.port] = .number(NumberSpec.parse("3000-5400"))
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.port), [3000, 5353])
    }

    func test_filterByProcessText() {
        var f = FilterState()
        f.byColumn[.process] = .text("post", regex: false)
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.processName), ["postgres"])
    }

    func test_filterByUser_tokens() {
        var f = FilterState()
        f.byColumn[.user] = .text("postgres, name", regex: false)
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(Set(r.map(\.processName)), Set(["node", "postgres", "Chrome"]))
    }

    func test_filterByProto_tokens() {
        var f = FilterState()
        f.byColumn[.proto] = .text("udp", regex: false)
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.processName), ["Chrome"])
    }

    func test_filterByCompound_textOnlyMatches() {
        var f = FilterState()
        f.byColumn[.user] = .compound(selected: [], text: "name")
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(Set(r.map(\.processName)), Set(["node", "Chrome"]))
    }

    func test_filterByCompound_selectionOnlyMatches() {
        var f = FilterState()
        f.byColumn[.user] = .compound(selected: ["_postgres"], text: "")
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.processName), ["postgres"])
    }

    func test_filterByCompound_textOrSelection() {
        var f = FilterState()
        f.byColumn[.user] = .compound(selected: ["_postgres"], text: "name")
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.count, 3)
    }

    func test_globalSearch_matchesPid() {
        var f = FilterState()
        f.globalSearch = "200"
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.pid), [200])
    }

    private func makeTimedEntries(now: Date) -> [PortEntry] {
        [
            PortEntry(id: "old", pid: 10, processName: "old", user: "u",
                      proto: .tcp, localAddress: "127.0.0.1", port: 1000, state: "LISTEN",
                      startTime: now.addingTimeInterval(-7200)),  // 2h ago
            PortEntry(id: "mid", pid: 20, processName: "mid", user: "u",
                      proto: .tcp, localAddress: "127.0.0.1", port: 2000, state: "LISTEN",
                      startTime: now.addingTimeInterval(-1800)),  // 30 min ago
            PortEntry(id: "new", pid: 30, processName: "new", user: "u",
                      proto: .tcp, localAddress: "127.0.0.1", port: 3000, state: "LISTEN",
                      startTime: now.addingTimeInterval(-60)),    // 1 min ago
        ]
    }

    func test_filterByTimeSpec_last5m() {
        // toRange uses Date() internally, so each entry's startTime is built relative to the current time.
        let now = Date()
        let entries = makeTimedEntries(now: now)
        var f = FilterState()
        f.byColumn[.started] = .timeSpec(TimeRangeSpec(mode: .last5m))
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: entries)
        // only "new" (1 min ago) is within last 5 min
        XCTAssertEqual(r.map(\.id), ["new"])
    }

    func test_filterByTimeSpec_last1h() {
        let now = Date()
        let entries = makeTimedEntries(now: now)
        var f = FilterState()
        f.byColumn[.started] = .timeSpec(TimeRangeSpec(mode: .last1h))
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: entries)
        // mid (30m) and new (1m) within last hour; old (2h) excluded
        XCTAssertEqual(Set(r.map(\.id)), Set(["mid", "new"]))
    }

    func test_filterByTimeSpec_customLast_10min() {
        let now = Date()
        let entries = makeTimedEntries(now: now)
        var f = FilterState()
        f.byColumn[.started] = .timeSpec(
            TimeRangeSpec(mode: .customLast, lastN: 10, lastUnit: "min")
        )
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: entries)
        // only "new" within last 10 min
        XCTAssertEqual(r.map(\.id), ["new"])
    }

    // MARK: - Augmentation lifecycle

    @MainActor
    func test_augmentation_doesNotRestartWhileInFlight() async {
        let runner = StubRunner()
        runner.nextStdout = Self.oneEntryLsof
        let scanner = PortScanner(runner: runner)
        let aug = GatedAugmenter()
        let vm = PortListViewModel(scanner: scanner, augmenter: aug)

        try? await vm.refreshOnce()                 // starts a pass, gated on first call
        await fulfillment(of: [aug.firstCallReached], timeout: 2)

        // Feed changed data (same PID) so applyBatch doesn't skip; the in-flight
        // guard must still prevent a second augmentation pass.
        runner.nextStdout = Self.oneEntryLsofAltPort
        try? await vm.refreshOnce()
        for _ in 0..<5 { await Task.yield() }       // give an erroneous pass a chance to run

        XCTAssertEqual(aug.count, 1, "augmentation must not restart while a pass is in flight")
        aug.release()
    }

    @MainActor
    func test_augmentation_notifiesObserversAndMerges() async {
        let runner = StubRunner()
        runner.nextStdout = Self.oneEntryLsof
        let scanner = PortScanner(runner: runner)
        let vm = PortListViewModel(scanner: scanner, augmenter: FillingAugmenter())

        try? await vm.refreshOnce()   // populates rawEntries; augmentation pass is queued

        // objectWillChange must fire when augmentation stores data (the pass
        // hasn't run yet — MainActor is busy until we await below).
        let exp = expectation(description: "augmentation notifies observers")
        exp.assertForOverFulfill = false
        var cancellables = Set<AnyCancellable>()
        vm.objectWillChange.sink { _ in exp.fulfill() }.store(in: &cancellables)

        await fulfillment(of: [exp], timeout: 2)
        XCTAssertEqual(vm.augmentedEntries.first?.executablePath, "/mock/exec")
        XCTAssertEqual(vm.augmentedEntries.first?.cwd, "/mock/cwd")
    }

    func test_filterByTimeSpec_anyMatchesAll() {
        let now = Date()
        let entries = makeTimedEntries(now: now)
        var f = FilterState()
        f.byColumn[.started] = .timeSpec(TimeRangeSpec(mode: .any))
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: entries)
        XCTAssertEqual(r.count, 3)
    }
}

final class PortListTableSortTests: XCTestCase {
    private func entry(_ id: String, pid: Int32, port: UInt16) -> PortEntry {
        PortEntry(id: id, pid: pid, processName: "p\(pid)", user: "u",
                  proto: .udp, localAddress: "*", port: port, state: nil)
    }

    /// Two PIDs both own port 5353 (each with a second port so both become groups).
    /// The group order must be deterministic (by PID) regardless of input order,
    /// not swap between refreshes.
    func test_groupsSharingPort_orderByPidDeterministically() {
        let entries = [
            entry("a1", pid: 6456, port: 5353),
            entry("a2", pid: 6456, port: 49850),
            entry("b1", pid: 22365, port: 5353),
            entry("b2", pid: 22365, port: 49724),
        ]
        let sort = SortSpec(column: .port, dir: .asc)
        func topGroupPids(_ input: [PortEntry]) -> [Int32] {
            PortListTable.buildRows(entries: input, filter: FilterState(),
                                    pinnedPorts: [], groupByPid: true,
                                    hideDuplicateRows: false, sort: sort)
                .filter { $0.kind == .group }
                .map { $0.pid }
        }
        let order = topGroupPids(entries)
        XCTAssertEqual(order, [6456, 22365])
        XCTAssertEqual(topGroupPids(entries.reversed()), order)
        XCTAssertEqual(topGroupPids([entries[3], entries[1], entries[2], entries[0]]), order)
    }
}
