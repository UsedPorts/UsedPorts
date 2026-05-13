import Foundation
import SwiftUI

@MainActor
public final class PortListViewModel: ObservableObject {
    @Published public private(set) var rawEntries: [PortEntry] = []
    @Published public var sort: SortSpec = SortSpec(column: .port, dir: .asc)
    @Published public var filter: FilterState = FilterState()
    @Published public var selection: Set<PortEntry.ID> = []
    @Published public var autoRefresh: Bool = true
    @Published public var windowVisible: Bool = true
    @Published public var columnCustomization: TableColumnCustomization<PortEntry> = TableColumnCustomization<PortEntry>()

    private let scanner: PortScanner
    private let toasts: ToastCenter?
    private var streamTask: Task<Void, Never>?
    private var currentBaseInterval: TimeInterval = 3.0

    private var augCache: [Int32: PortEntry] = [:]
    private var augTask: Task<Void, Never>?
    private let augmenter: ProcessAugmenting

    private let customizationKey = "UsedPorts.tableColumnCustomization"

    public init(scanner: PortScanner, toasts: ToastCenter? = nil, augmenter: ProcessAugmenting = ProcessAugmenter()) {
        self.scanner = scanner
        self.toasts = toasts
        self.augmenter = augmenter
        if let data = UserDefaults.standard.data(forKey: customizationKey),
           let decoded = try? JSONDecoder().decode(TableColumnCustomization<PortEntry>.self, from: data) {
            self.columnCustomization = decoded
        }
    }

    public func persistCustomization() {
        if let data = try? JSONEncoder().encode(columnCustomization) {
            UserDefaults.standard.set(data, forKey: customizationKey)
        }
    }

    public var visibleEntries: [PortEntry] {
        let merged = rawEntries.map { e -> PortEntry in
            if let cached = augCache[e.pid] {
                var out = e
                out.executablePath = cached.executablePath
                out.cwd = cached.cwd
                out.startTime = cached.startTime
                return out
            }
            return e
        }
        return Self.apply(sort: sort, filter: filter, to: merged)
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
        case (.proto, .text(let t, _)):
            return matchesTokens(t, against: e.proto.rawValue)
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
        case (.address, .text(let t, _)):
            return AddressMatcher.matches(localAddress: e.localAddress, query: t)
        case (.state, .multiSelect(let set)): return set.contains(e.state ?? "")
        case (.state, .text(let t, _)):
            return matchesTokens(t, against: e.state ?? "")
        case (.user, .multiSelect(let set)): return set.contains(e.user)
        case (.user, .text(let t, _)):
            return matchesTokens(t, against: e.user)
        case (.proto, .compound(let sel, let t)):
            let proto = e.proto.rawValue
            if sel.contains(proto) { return true }
            if !t.isEmpty, Self.matchesTokens(t, against: proto) { return true }
            if sel.isEmpty && t.isEmpty { return true }
            return false
        case (.state, .compound(let sel, let t)):
            let st = e.state ?? ""
            if sel.contains(st) { return true }
            if !t.isEmpty, Self.matchesTokens(t, against: st) { return true }
            if sel.isEmpty && t.isEmpty { return true }
            return false
        case (.user, .compound(let sel, let t)):
            if sel.contains(e.user) { return true }
            if !t.isEmpty, Self.matchesTokens(t, against: e.user) { return true }
            if sel.isEmpty && t.isEmpty { return true }
            return false
        case (.address, .compound(let sel, let t)):
            if sel.contains(e.localAddress) { return true }
            if !t.isEmpty, AddressMatcher.matches(localAddress: e.localAddress, query: t) { return true }
            if sel.isEmpty && t.isEmpty { return true }
            return false
        case (.ipFamily, .multiSelect(let set)): return set.contains(e.ipFamily?.rawValue ?? "")
        case (.ipFamily, .text(let t, _)):
            return matchesTokens(t, against: e.ipFamily?.rawValue ?? "")
        case (.ipFamily, .compound(let sel, let t)):
            let f = e.ipFamily?.rawValue ?? ""
            if sel.contains(f) { return true }
            if !t.isEmpty, Self.matchesTokens(t, against: f) { return true }
            if sel.isEmpty && t.isEmpty { return true }
            return false
        case (.started, .timeRange(let from, let to)):
            if from == nil && to == nil { return true }
            // Rows whose startTime has not yet been populated by ProcessAugmenter are passed through conservatively.
            guard let st = e.startTime else { return true }
            if let from, st < from { return false }
            if let to, st > to { return false }
            return true
        case (.started, .timeSpec(let spec)):
            let (from, to) = spec.toRange()
            if from == nil && to == nil { return true }
            guard let st = e.startTime else { return true }
            if let from, st < from { return false }
            if let to, st > to { return false }
            return true
        default: return true
        }
    }

    private nonisolated static func matchesTokens(_ query: String, against value: String) -> Bool {
        let tokens = query
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return true }
        return tokens.contains { value.localizedCaseInsensitiveContains($0) }
    }

    public nonisolated static func compare(_ a: PortEntry, _ b: PortEntry, _ s: SortSpec) -> Bool {
        let asc = s.dir == .asc
        switch s.column {
        case .pid: return asc ? a.pid < b.pid : a.pid > b.pid
        case .port: return asc ? a.port < b.port : a.port > b.port
        case .proto: return asc ? a.proto.rawValue < b.proto.rawValue : a.proto.rawValue > b.proto.rawValue
        case .ipFamily:
            let av = a.ipFamily?.rawValue ?? ""
            let bv = b.ipFamily?.rawValue ?? ""
            return asc ? av < bv : av > bv
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
        currentBaseInterval = interval
        let effective = effectiveInterval(base: interval)
        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.scanner.startPolling(intervalSeconds: effective)
            for await batch in stream {
                if !Task.isCancelled {
                    self.applyBatch(batch)
                }
            }
        }
    }

    public func bootstrapIfNeeded(interval: TimeInterval = 3.0) {
        guard streamTask == nil else { return }
        startStream(interval: interval)
    }

    public func setWindowVisible(_ visible: Bool) {
        let was = windowVisible
        windowVisible = visible
        if was != visible, streamTask != nil {
            startStream(interval: currentBaseInterval)
        }
        if !visible {
            augTask?.cancel()
            augTask = nil
        } else {
            startAugmentation()
        }
    }

    private func startAugmentation() {
        augTask?.cancel()
        let entries = rawEntries
        augTask = Task { [weak self] in
            guard let self else { return }
            for entry in entries {
                if Task.isCancelled { return }
                if self.hasCache(for: entry.pid) { continue }
                let aug = await self.augmenter.augment(entry)
                if Task.isCancelled { return }
                self.storeAug(pid: entry.pid, entry: aug)
            }
        }
    }

    private func hasCache(for pid: Int32) -> Bool {
        return augCache[pid] != nil
    }

    private func storeAug(pid: Int32, entry: PortEntry) {
        augCache[pid] = entry
        // Trigger a UI refresh by re-emitting rawEntries (publisher).
        let snapshot = rawEntries
        rawEntries = snapshot
    }

    private func effectiveInterval(base: TimeInterval) -> TimeInterval {
        return windowVisible ? base : base * 2
    }

    private func applyBatch(_ batch: [PortEntry]) {
        let prevSelected = selection
        rawEntries = batch
        let liveIds = Set(batch.map(\.id))
        let stillAlive = prevSelected.intersection(liveIds)
        if !prevSelected.isEmpty, stillAlive.isEmpty {
            selection = []
            toasts?.showToast(String(localized: "Selected process has terminated"))
        } else if stillAlive != prevSelected {
            // Some entries disappeared — keep only the ones still alive.
            selection = stillAlive
        }
        // Prune cache entries whose PIDs no longer exist.
        let livePids = Set(batch.map { $0.pid })
        augCache = augCache.filter { livePids.contains($0.key) }
        if windowVisible {
            startAugmentation()
        }
    }

    public func stopStream() async {
        streamTask?.cancel()
        streamTask = nil
        await scanner.stopPolling()
    }

    public func refreshOnce() async throws {
        let batch = try await scanner.scanOnce()
        applyBatch(batch)
    }
}
