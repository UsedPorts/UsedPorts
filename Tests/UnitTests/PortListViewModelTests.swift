import XCTest
@testable import UsedPorts

final class PortListViewModelTests: XCTestCase {
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
