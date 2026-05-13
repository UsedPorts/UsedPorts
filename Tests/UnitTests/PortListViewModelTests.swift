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

    func test_globalSearch_matchesPid() {
        var f = FilterState()
        f.globalSearch = "200"
        let r = PortListViewModel.apply(
            sort: SortSpec(column: .port, dir: .asc),
            filter: f,
            to: makeEntries())
        XCTAssertEqual(r.map(\.pid), [200])
    }
}
