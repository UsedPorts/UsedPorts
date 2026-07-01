import Foundation
import SwiftUI
import AppKit

@MainActor
public final class PortListViewModel: ObservableObject {
    @Published public private(set) var rawEntries: [PortEntry] = []
    @Published public var sort: SortSpec = SortSpec(column: .port, dir: .asc)
    @Published public var filter: FilterState = FilterState()
    @Published public var selection: Set<PortEntry.ID> = []
    @Published public var autoRefresh: Bool = true
    @Published public var windowVisible: Bool = true
    @Published var columnCustomization: TableColumnCustomization<PortTableRow> = TableColumnCustomization<PortTableRow>()

    private let scanner: PortScanner
    private let toasts: ToastCenter?
    private var streamTask: Task<Void, Never>?
    private var currentBaseInterval: TimeInterval = 3.0
    // Effective (visibility-adjusted) interval the running stream is polling at, so we can
    // skip a needless restart when a visibility change doesn't actually change the cadence.
    private var currentEffectiveInterval: TimeInterval = 0
    private var backgroundRefreshMode: BackgroundRefreshMode = .slower

    private var augCache: [Int32: ProcessAugmentation] = [:]
    private var augTask: Task<Void, Never>?
    private var isAugmenting = false
    private let augmenter: ProcessAugmenting

    /// Caches per-process app icons for the optional process-icon feature
    /// (AppSettings.showProcessIcons). Pruned each poll in applyBatch.
    let iconProvider = ProcessIconProvider()

    private let customizationKey = "UsedPorts.tableColumnCustomization"

    public init(scanner: PortScanner, toasts: ToastCenter? = nil, augmenter: ProcessAugmenting = ProcessAugmenter()) {
        self.scanner = scanner
        self.toasts = toasts
        self.augmenter = augmenter
        if let data = UserDefaults.standard.data(forKey: customizationKey),
           let decoded = try? JSONDecoder().decode(TableColumnCustomization<PortTableRow>.self, from: data) {
            self.columnCustomization = decoded
        }
    }

    /// App icon for a pid, or nil for CLI/daemon processes. Cache-backed; lookups don't
    /// trigger re-renders (the cache is not @Published).
    public func processIcon(forPID pid: pid_t) -> NSImage? {
        iconProvider.icon(forPID: pid)
    }

    public func persistCustomization() {
        if let data = try? JSONEncoder().encode(columnCustomization) {
            UserDefaults.standard.set(data, forKey: customizationKey)
        }
    }

    /// rawEntries with cached augment data (executable path, cwd, startTime) merged in.
    /// No filter or sort applied. Used by views that want to apply their own filter
    /// behavior (e.g. PID-grouping dims non-matching groups instead of hiding them).
    public var augmentedEntries: [PortEntry] {
        rawEntries.map { e -> PortEntry in
            if let cached = augCache[e.pid] {
                var out = e
                out.executablePath = cached.executablePath
                out.cwd = cached.cwd
                out.startTime = cached.startTime
                return out
            }
            return e
        }
    }

    public var visibleEntries: [PortEntry] {
        Self.apply(sort: sort, filter: filter, to: augmentedEntries)
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

    public func startStream(interval: TimeInterval = 3.0, immediateScan: Bool = true) {
        streamTask?.cancel()
        currentBaseInterval = interval
        let effective = effectiveInterval(base: interval)
        currentEffectiveInterval = effective
        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.scanner.startPolling(intervalSeconds: effective, immediateFirstScan: immediateScan)
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
        if was != visible {
            // Only force an immediate rescan when *showing* (fresh data on open).
            // Hiding just reschedules the cadence — no wasteful scan on the way out.
            applyStreamForCurrentState(immediateScan: visible)
        }
        if !visible {
            augTask?.cancel()
            augTask = nil
        } else {
            startAugmentation()
        }
    }

    /// Restart, stop, or leave the polling stream alone based on visibility + background mode.
    /// Centralized so visibility changes, interval changes, and mode changes go through one path.
    private func applyStreamForCurrentState(immediateScan: Bool) {
        if !windowVisible && backgroundRefreshMode == .paused {
            if streamTask != nil {
                Task { await stopStream() }
            }
            return
        }
        guard autoRefresh else { return }
        // If a stream is already running at the same effective cadence, leave it be —
        // tearing it down would trigger a needless rescan + full UI rebuild on every
        // show/hide toggle.
        if streamTask != nil, effectiveInterval(base: currentBaseInterval) == currentEffectiveInterval {
            return
        }
        startStream(interval: currentBaseInterval, immediateScan: immediateScan)
    }

    /// Updates the base poll interval and restarts the stream if it's currently running.
    public func setRefreshInterval(_ interval: TimeInterval) {
        guard interval > 0, currentBaseInterval != interval else { return }
        currentBaseInterval = interval
        if streamTask != nil {
            startStream(interval: interval, immediateScan: false)
        }
    }

    /// Updates the background-refresh mode. Restarts (or pauses) the stream to apply.
    public func setBackgroundRefreshMode(_ mode: BackgroundRefreshMode) {
        guard backgroundRefreshMode != mode else { return }
        backgroundRefreshMode = mode
        applyStreamForCurrentState(immediateScan: false)
    }

    private func startAugmentation() {
        // A pass is already running; let it finish rather than cancelling its
        // in-flight subprocess work on every poll.
        // ponytail: relies on augmenter.augment(pids:) always returning (CommandRunner
        // times out at ~2s); a permanently hung augment would stall augmentation.
        guard !isAugmenting else { return }
        // Only the PIDs we haven't resolved yet — steady state (all cached) does no work.
        let uncached = Array(Set(rawEntries.map(\.pid)).subtracting(augCache.keys)).filter { $0 > 0 }
        guard !uncached.isEmpty else { return }
        isAugmenting = true
        augTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isAugmenting = false; self.augTask = nil }
            let infos = await self.augmenter.augment(pids: uncached)
            if Task.isCancelled { return }
            for (pid, info) in infos { self.augCache[pid] = info }
            // One publish for the whole batch (augmentedEntries reads augCache).
            self.objectWillChange.send()
        }
    }

    private func effectiveInterval(base: TimeInterval) -> TimeInterval {
        if windowVisible { return base }
        switch backgroundRefreshMode {
        case .same: return base
        case .slower: return base * 2
        case .paused: return base   // not used — paused mode stops the stream entirely
        }
    }

    private func applyBatch(_ batch: [PortEntry]) {
        // Nothing changed since the last poll — skip the whole downstream rebuild
        // (publish, selection reconcile, table/menu re-render, augmentation pass).
        guard batch != rawEntries else { return }
        let prevSelected = selection
        rawEntries = batch
        let liveIds = Set(batch.map(\.id))
        let livePids = Set(batch.map { $0.pid })
        iconProvider.prune(livePIDs: livePids)
        // Group rows live under "group-{pid}" ids; they stay selected as long as the PID
        // still has any port in the batch. Leaf ids must match an entry id exactly.
        var stillAlive: Set<PortEntry.ID> = []
        for id in prevSelected {
            if id.hasPrefix("group-"),
               let pid = Int32(id.dropFirst("group-".count)) {
                if livePids.contains(pid) { stillAlive.insert(id) }
            } else if liveIds.contains(id) {
                stillAlive.insert(id)
            }
        }
        if !prevSelected.isEmpty, stillAlive.isEmpty {
            selection = []
            toasts?.showToast(String(localized: "Selected process has terminated"))
        } else if stillAlive != prevSelected {
            // Some entries disappeared — keep only the ones still alive.
            selection = stillAlive
        }
        // Prune cache entries whose PIDs no longer exist.
        augCache = augCache.filter { livePids.contains($0.key) }
        if windowVisible {
            startAugmentation()
        }
    }

    public func stopStream() async {
        streamTask?.cancel()
        streamTask = nil
        currentEffectiveInterval = 0
        await scanner.stopPolling()
    }

    public func refreshOnce() async throws {
        let batch = try await scanner.scanOnce()
        applyBatch(batch)
    }
}
