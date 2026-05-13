import Foundation
import SwiftUI

@MainActor
public final class PortListViewModel: ObservableObject {
    @Published public private(set) var rawEntries: [PortEntry] = []
    @Published public var sort: SortSpec = SortSpec(column: .port, dir: .asc)
    @Published public var filter: FilterState = FilterState()
    @Published public var selection: PortEntry.ID? = nil
    @Published public var autoRefresh: Bool = true

    private let scanner: PortScanner
    private var streamTask: Task<Void, Never>?

    public init(scanner: PortScanner) { self.scanner = scanner }

    public var visibleEntries: [PortEntry] {
        Self.apply(sort: sort, filter: filter, to: rawEntries)
    }

    public nonisolated static func apply(sort: SortSpec, filter: FilterState, to entries: [PortEntry]) -> [PortEntry] {
        let filtered = entries.filter { matches(filter, $0) }
        return filtered.sorted { compare($0, $1, sort) }
    }

    public nonisolated static func matches(_ f: FilterState, _ e: PortEntry) -> Bool {
        if !f.globalSearch.isEmpty {
            let q = f.globalSearch.lowercased()
            let hay = "\(e.pid) \(e.port) \(e.processName) \(e.localAddress) \(e.user)".lowercased()
            if !hay.contains(q) { return false }
        }
        for (col, cf) in f.byColumn where !cf.isEmpty {
            if !columnMatch(col, cf, e) { return false }
        }
        return true
    }

    private nonisolated static func columnMatch(_ col: PortColumn, _ cf: ColumnFilter, _ e: PortEntry) -> Bool {
        switch (col, cf) {
        case (.pid, .number(let s)): return s.matches(Int(e.pid))
        case (.port, .number(let s)): return s.matches(Int(e.port))
        case (.proto, .multiSelect(let set)): return set.contains(e.proto.rawValue)
        case (.process, .text(let t, let regex)):
            if regex {
                if let re = try? NSRegularExpression(pattern: t) {
                    let range = NSRange(location: 0, length: e.processName.utf16.count)
                    return re.firstMatch(in: e.processName, range: range) != nil
                }
                return false
            } else {
                return e.processName.localizedCaseInsensitiveContains(t)
            }
        case (.address, .multiSelect(let set)): return set.contains(e.localAddress)
        case (.address, .text(let t, _)): return e.localAddress.contains(t)
        case (.state, .multiSelect(let set)): return set.contains(e.state ?? "")
        case (.user, .multiSelect(let set)): return set.contains(e.user)
        case (.started, .timeRange(let from, let to)):
            guard let st = e.startTime else { return from == nil && to == nil }
            if let from, st < from { return false }
            if let to, st > to { return false }
            return true
        default: return true
        }
    }

    public nonisolated static func compare(_ a: PortEntry, _ b: PortEntry, _ s: SortSpec) -> Bool {
        let asc = s.dir == .asc
        switch s.column {
        case .pid: return asc ? a.pid < b.pid : a.pid > b.pid
        case .port: return asc ? a.port < b.port : a.port > b.port
        case .proto: return asc ? a.proto.rawValue < b.proto.rawValue : a.proto.rawValue > b.proto.rawValue
        case .process: return asc ? a.processName < b.processName : a.processName > b.processName
        case .address: return asc ? a.localAddress < b.localAddress : a.localAddress > b.localAddress
        case .state: return asc ? (a.state ?? "") < (b.state ?? "") : (a.state ?? "") > (b.state ?? "")
        case .user: return asc ? a.user < b.user : a.user > b.user
        case .started:
            let av = a.startTime ?? .distantPast
            let bv = b.startTime ?? .distantPast
            return asc ? av < bv : av > bv
        }
    }

    public func startStream(interval: TimeInterval = 3.0) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.scanner.startPolling(intervalSeconds: interval)
            for await batch in stream {
                if !Task.isCancelled {
                    self.rawEntries = batch
                }
            }
        }
    }

    public func stopStream() async {
        streamTask?.cancel()
        await scanner.stopPolling()
    }

    public func refreshOnce() async throws {
        rawEntries = try await scanner.scanOnce()
    }
}
