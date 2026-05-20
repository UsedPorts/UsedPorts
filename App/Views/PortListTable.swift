import SwiftUI

/// Composite sort key used by both group and leaf rows. Pin priority is encoded into
/// `primary` itself with a sort-direction-dependent prefix (so pinned rows stay at the
/// top whether the user picked ascending or descending); the column value follows the
/// prefix, with the port number as a stable tie-breaker.
struct RowSortKey: Comparable, Hashable {
    let primary: String
    let tieBreaker: Int

    static func < (a: Self, b: Self) -> Bool {
        if a.primary != b.primary { return a.primary < b.primary }
        return a.tieBreaker < b.tieBreaker
    }
}

/// Builds the `primary` field of a `RowSortKey` so that pinned rows are always "first"
/// after `KeyPathComparator` applies its order. Forward sort wants pinned rows to be
/// the smallest; reverse sort wants them the largest, since SwiftUI inverts the result.
private func sortPrimary(_ value: String, isPinned: Bool, sortDir: SortDir) -> String {
    let pinChar: Character
    switch sortDir {
    case .asc:  pinChar = isPinned ? "0" : "1"
    case .desc: pinChar = isPinned ? "1" : "0"
    }
    return String(pinChar) + "\u{1F}" + value
}

/// Hierarchical row model for the main table. Both single-port rows and PID-grouped
/// parent rows use the same struct; groups carry `children`, leaves leave it nil.
/// Group rows override every column's sort key to a PID-derived value so the top-level
/// ordering is always by PID regardless of which column the user clicks — children
/// inside each group still sort by the user's column choice (the spec: groups stay
/// stable, children follow the user's sort).
struct PortTableRow: Identifiable, Hashable {
    enum Kind { case leaf, group }

    let id: String
    let kind: Kind
    let pid: Int32

    // Display labels (groups join multiple values with ", "; ports collapse continuous ranges)
    let processName: String
    let portsLabel: String
    let protoLabel: String
    let ipLabel: String
    let addressLabel: String
    let stateLabel: String
    let userLabel: String
    let startedLabel: String

    let dimmed: Bool
    let isPinned: Bool

    let sortPid: RowSortKey
    let sortPort: RowSortKey
    let sortProcess: RowSortKey
    let sortProto: RowSortKey
    let sortIP: RowSortKey
    let sortAddress: RowSortKey
    let sortState: RowSortKey
    let sortUser: RowSortKey
    let sortStarted: RowSortKey

    let children: [PortTableRow]?
    let backingEntries: [PortEntry]

    static func == (a: PortTableRow, b: PortTableRow) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct PortListTable: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var settings: AppSettings
    @State private var openColumn: PortColumn? = nil
    /// PIDs whose group rows are currently disclosed. PortOutlineView reads/writes this
    /// via a Binding; we also auto-expand whenever the user selects a group so its
    /// children show up under the native NSOutlineView highlight.
    @State private var expandedGroups: Set<Int32> = []

    private var rows: [PortTableRow] {
        Self.buildRows(
            entries: viewModel.augmentedEntries,
            filter: viewModel.filter,
            pinnedPorts: settings.pinnedPorts,
            groupByPid: settings.groupByPid,
            hideDuplicateRows: settings.hideDuplicateRows,
            sort: viewModel.sort
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            columnChips
            PortOutlineView(
                rows: rows,
                selection: $viewModel.selection,
                sort: $viewModel.sort,
                expandedGroups: $expandedGroups
            )
            .onChange(of: viewModel.selection) { oldValue, newValue in
                // Only auto-expand groups that just entered the selection. Keeping group
                // ids in the augmented set means newValue always carries them, so without
                // this diff the disclosure would re-open immediately when the user collapses
                // it manually.
                let newlyAdded = newValue.subtracting(oldValue)
                for id in newlyAdded where id.hasPrefix("group-") {
                    if let pid = Int32(id.dropFirst("group-".count)) {
                        expandedGroups.insert(pid)
                    }
                }
                syncAugmentedSelection()
            }
            .onChange(of: expandedGroups) { _, _ in syncAugmentedSelection() }
            .onChange(of: viewModel.rawEntries) { _, _ in syncAugmentedSelection() }
        }
    }

    /// SwiftUI Table reads the selection binding on its own schedule and won't re-derive
    /// row highlight from a get-only wrapper when a disclosure expands. Instead we keep
    /// the child entry ids inside `viewModel.selection` itself and let SwiftUI bind to it
    /// directly. `syncAugmentedSelection()` runs whenever the selection, expansion state,
    /// or live entries change, refilling the augmented set so newly visible children
    /// always carry the native highlight.
    private func syncAugmentedSelection() {
        let visible = settings.hideDuplicateRows
            ? Self.deduplicated(viewModel.rawEntries)
            : viewModel.rawEntries
        let augmented = Self.expandGroupSelection(viewModel.selection, visibleEntries: visible)
        if augmented != viewModel.selection {
            viewModel.selection = augmented
        }
    }

    private static func expandGroupSelection(_ selection: Set<PortEntry.ID>, visibleEntries: [PortEntry]) -> Set<PortEntry.ID> {
        var out = selection
        for id in selection where id.hasPrefix("group-") {
            guard let pid = Int32(id.dropFirst("group-".count)) else { continue }
            for entry in visibleEntries where entry.pid == pid {
                out.insert(entry.id)
            }
        }
        return out
    }

    private var columnChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PortColumn.allCases, id: \.self) { col in
                    let isActive = (viewModel.filter.byColumn[col]?.isEmpty == false)
                    HStack(spacing: 6) {
                        Button {
                            openColumn = col
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "line.3.horizontal.decrease").font(.callout)
                                Text(label(col))
                                    .font(.callout)
                                    .fontWeight(isActive ? .semibold : .regular)
                                if isActive {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(isActive
                              ? String(localized: "Filter: \(label(col)) (active)")
                              : String(localized: "Filter: \(label(col))"))

                        if isActive {
                            Button {
                                viewModel.filter.byColumn.removeValue(forKey: col)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.callout)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Clear filter: \(label(col))"))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .popover(isPresented: Binding(
                        get: { openColumn == col },
                        set: { if !$0 { openColumn = nil } }
                    )) {
                        ColumnFilterPopover(
                            column: col,
                            availableValues: dynamicValues(for: col),
                            viewModel: viewModel,
                            isPresented: Binding(
                                get: { openColumn == col },
                                set: { if !$0 { openColumn = nil } }
                            )
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func label(_ c: PortColumn) -> String {
        switch c {
        case .pid: return "PID"
        case .port: return "Port"
        case .proto: return "Proto"
        case .ipFamily: return "IP"
        case .process: return "Process"
        case .address: return "Address"
        case .state: return "State"
        case .user: return "User"
        case .started: return "Started"
        }
    }

    private func dynamicValues(for c: PortColumn) -> [String] {
        switch c {
        case .address:  return Array(Set(viewModel.rawEntries.map { $0.localAddress })).sorted()
        case .state:
            var values = Set(viewModel.rawEntries.compactMap { $0.state })
            if viewModel.rawEntries.contains(where: { $0.state == nil }) {
                values.insert("")
            }
            return Array(values).sorted()
        case .user:     return Array(Set(viewModel.rawEntries.map { $0.user })).sorted()
        case .ipFamily: return ["IPv4", "IPv6"]
        default:        return []
        }
    }

    // MARK: - Row building (static so it stays unit-testable)

    static func buildRows(
        entries: [PortEntry],
        filter: FilterState,
        pinnedPorts: Set<UInt16>,
        groupByPid: Bool,
        hideDuplicateRows: Bool,
        sort: SortSpec
    ) -> [PortTableRow] {
        let deduped = hideDuplicateRows ? deduplicated(entries) : entries

        if !groupByPid {
            let leaves: [PortTableRow] = deduped.compactMap { entry in
                guard PortListViewModel.matches(filter, entry) else { return nil }
                let pinned = pinnedPorts.contains(entry.port)
                return makeLeafRow(entry: entry, isPinned: pinned, dimmed: false, sortDir: sort.dir)
            }
            return sortRows(leaves, sort: sort)
        }

        // Grouped: groups with at least one matching child are shown. Non-matching children
        // inside a kept group still render (dim) so the user keeps context for the process.
        let groups = Dictionary(grouping: deduped, by: { $0.pid })
        var out: [PortTableRow] = []
        out.reserveCapacity(groups.count)
        for (pid, members) in groups {
            let anyChildPinned = members.contains { pinnedPorts.contains($0.port) }
            let anyChildMatches = members.contains { PortListViewModel.matches(filter, $0) }
            guard anyChildMatches else { continue }

            if members.count <= 1, let entry = members.first {
                let pinned = pinnedPorts.contains(entry.port)
                out.append(makeLeafRow(entry: entry, isPinned: pinned, dimmed: false, sortDir: sort.dir))
                continue
            }

            let unsorted = members.map { entry -> PortTableRow in
                let pinned = pinnedPorts.contains(entry.port)
                let dim = !PortListViewModel.matches(filter, entry)
                return makeLeafRow(entry: entry, isPinned: pinned, dimmed: dim, sortDir: sort.dir)
            }
            let children = sortRows(unsorted, sort: sort)
            out.append(makeGroupRow(pid: pid,
                                    members: members,
                                    isPinned: anyChildPinned,
                                    dimmed: false,
                                    children: children,
                                    pinnedPorts: pinnedPorts,
                                    sort: sort))
        }
        return sortRows(out, sort: sort)
    }

    /// Sorts top-level or child rows by the active column. Both directions read from each
    /// row's RowSortKey, which already encodes pin priority via its primary-string prefix.
    private static func sortRows(_ rows: [PortTableRow], sort: SortSpec) -> [PortTableRow] {
        rows.sorted { a, b in
            let ka = sortKey(of: a, for: sort.column)
            let kb = sortKey(of: b, for: sort.column)
            return sort.dir == .asc ? (ka < kb) : (kb < ka)
        }
    }

    private static func sortKey(of row: PortTableRow, for column: PortColumn) -> RowSortKey {
        switch column {
        case .pid: return row.sortPid
        case .port: return row.sortPort
        case .process: return row.sortProcess
        case .proto: return row.sortProto
        case .ipFamily: return row.sortIP
        case .address: return row.sortAddress
        case .state: return row.sortState
        case .user: return row.sortUser
        case .started: return row.sortStarted
        }
    }

    /// Keeps the first occurrence per (pid, port, proto, ipFamily, localAddress, state, user, process).
    /// Differs only by file descriptor — lsof reports each fd separately, and dup/multi-listener
    /// sockets otherwise appear as visual duplicates in the table.
    static func deduplicated(_ entries: [PortEntry]) -> [PortEntry] {
        var seen: Set<String> = []
        var out: [PortEntry] = []
        out.reserveCapacity(entries.count)
        for e in entries {
            let key = "\(e.pid)\u{1F}\(e.port)\u{1F}\(e.proto.rawValue)\u{1F}\(e.ipFamily?.rawValue ?? "")\u{1F}\(e.localAddress)\u{1F}\(e.state ?? "")\u{1F}\(e.user)\u{1F}\(e.processName)"
            if seen.insert(key).inserted {
                out.append(e)
            }
        }
        return out
    }

    private static func makeLeafRow(entry e: PortEntry, isPinned: Bool, dimmed: Bool, sortDir: SortDir) -> PortTableRow {
        let tie = Int(e.port)
        func key(_ value: String) -> RowSortKey {
            RowSortKey(primary: sortPrimary(value, isPinned: isPinned, sortDir: sortDir), tieBreaker: tie)
        }
        return PortTableRow(
            id: e.id,
            kind: .leaf,
            pid: e.pid,
            processName: e.processName,
            portsLabel: "\(e.port)",
            protoLabel: e.proto.rawValue,
            ipLabel: e.ipFamily?.rawValue ?? "—",
            addressLabel: e.localAddress,
            stateLabel: e.state ?? "—",
            userLabel: e.user,
            startedLabel: e.startTime.map { formatStarted($0) } ?? "—",
            dimmed: dimmed,
            isPinned: isPinned,
            sortPid: key(padInt(Int(e.pid))),
            sortPort: key(padInt(Int(e.port))),
            sortProcess: key(e.processName),
            sortProto: key(e.proto.rawValue),
            sortIP: key(e.ipFamily?.rawValue ?? ""),
            sortAddress: key(e.localAddress),
            sortState: key(e.state ?? ""),
            sortUser: key(e.user),
            sortStarted: key(dateSortString(e.startTime)),
            children: nil,
            backingEntries: [e]
        )
    }

    private static func makeGroupRow(pid: Int32,
                                     members: [PortEntry],
                                     isPinned: Bool,
                                     dimmed: Bool,
                                     children: [PortTableRow],
                                     pinnedPorts: Set<UInt16>,
                                     sort: SortSpec) -> PortTableRow {
        let sortDir = sort.dir
        // The group's representative for each column comes from its children: forward sort
        // picks the smallest child key, reverse picks the largest. Children already encode
        // pin priority in their primary prefix, so a group with any pinned child is anchored
        // to that pinned position in either direction.
        let useMin = sortDir == .asc

        func rep(_ keys: [RowSortKey]) -> RowSortKey {
            let pick: RowSortKey?
            if useMin {
                pick = keys.min()
            } else {
                pick = keys.max()
            }
            return pick ?? RowSortKey(
                primary: sortPrimary(padInt(Int(pid)), isPinned: isPinned, sortDir: sortDir),
                tieBreaker: Int(pid)
            )
        }

        // Labels follow the children's display order so the joined values line up with the
        // rows the user actually sees: the first distinct value the user would scroll past
        // appears first in the label. Ports are split into pinned vs rest first (pinned
        // chunk always leads) and range-compressed when the user is sorting by Port.
        let portsLabel = makePortsLabel(children: children, pinnedPorts: pinnedPorts, sort: sort)
        let protoLabel = orderedUniqueJoined(children.map { $0.protoLabel })
        let ipLabel = orderedUniqueJoined(children.map { $0.ipLabel })
        let addressLabel = orderedUniqueJoined(children.map { $0.addressLabel })
        let stateLabel = orderedUniqueJoined(children.map { $0.stateLabel })
        let processName = members.first?.processName ?? ""
        let userLabel = members.first?.user ?? ""
        let startedLabel: String = members.first?.startTime.map { formatStarted($0) } ?? "—"

        return PortTableRow(
            id: "group-\(pid)",
            kind: .group,
            pid: pid,
            processName: processName,
            portsLabel: portsLabel,
            protoLabel: protoLabel,
            ipLabel: ipLabel,
            addressLabel: addressLabel,
            stateLabel: stateLabel,
            userLabel: userLabel,
            startedLabel: startedLabel,
            dimmed: dimmed,
            isPinned: isPinned,
            sortPid: rep(children.map { $0.sortPid }),
            sortPort: rep(children.map { $0.sortPort }),
            sortProcess: rep(children.map { $0.sortProcess }),
            sortProto: rep(children.map { $0.sortProto }),
            sortIP: rep(children.map { $0.sortIP }),
            sortAddress: rep(children.map { $0.sortAddress }),
            sortState: rep(children.map { $0.sortState }),
            sortUser: rep(children.map { $0.sortUser }),
            sortStarted: rep(children.map { $0.sortStarted }),
            children: children,
            backingEntries: members
        )
    }

    private static func padInt(_ n: Int) -> String { String(format: "%012d", n) }

    private static func dateSortString(_ d: Date?) -> String {
        guard let d else { return "" }
        return String(format: "%020.4f", d.timeIntervalSinceReferenceDate)
    }

    private static func formatStarted(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: d)
    }

    /// Joins distinct values in the order they first appear (first-seen wins). Used for
    /// group labels so the joined string mirrors the order of the rendered child rows.
    private static func orderedUniqueJoined(_ values: [String]) -> String {
        var seen: Set<String> = []
        var out: [String] = []
        for v in values where seen.insert(v).inserted {
            out.append(v)
        }
        return out.joined(separator: ", ")
    }

    /// Builds the group's Port label by reading port numbers in the children's display
    /// order. Pinned ports lead, then the rest follow; when the user is sorting by Port,
    /// consecutive runs collapse into "1024-1026" honoring the active direction.
    private static func makePortsLabel(children: [PortTableRow],
                                       pinnedPorts: Set<UInt16>,
                                       sort: SortSpec) -> String {
        var seen: Set<UInt16> = []
        var pinnedSeq: [UInt16] = []
        var restSeq: [UInt16] = []
        for child in children {
            guard let p = child.backingEntries.first?.port else { continue }
            if !seen.insert(p).inserted { continue }
            if pinnedPorts.contains(p) { pinnedSeq.append(p) } else { restSeq.append(p) }
        }
        let compress = sort.column == .port
        let asc = sort.dir == .asc
        let pinnedLabel = formatPortsOrdered(pinnedSeq, compress: compress, asc: asc)
        let restLabel = formatPortsOrdered(restSeq, compress: compress, asc: asc)
        return [pinnedLabel, restLabel].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Formats an ordered port sequence. With `compress` and a strictly ±1 run, neighbours
    /// collapse to "start-end"; otherwise each port is emitted verbatim in input order.
    private static func formatPortsOrdered(_ ports: [UInt16], compress: Bool, asc: Bool) -> String {
        guard !ports.isEmpty else { return "" }
        if !compress {
            return ports.map { "\($0)" }.joined(separator: ", ")
        }
        let step = asc ? 1 : -1
        var result: [String] = []
        var start = ports[0]
        var prev = ports[0]
        for p in ports.dropFirst() {
            if Int(p) == Int(prev) + step {
                prev = p
            } else {
                result.append(start == prev ? "\(start)" : "\(start)-\(prev)")
                start = p
                prev = p
            }
        }
        result.append(start == prev ? "\(start)" : "\(start)-\(prev)")
        return result.joined(separator: ", ")
    }

}
