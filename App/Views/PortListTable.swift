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
    @State private var sortOrder: [KeyPathComparator<PortTableRow>] = [
        KeyPathComparator(\PortTableRow.sortPort, order: .forward)
    ]

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
            tableView
                .onChange(of: sortOrder) { _, new in
                    if let first = new.first {
                        viewModel.sort = Self.sortSpec(from: first)
                    }
                }
                .onChange(of: viewModel.sort) { _, new in
                    let comp = Self.comparator(from: new)
                    if let cur = sortOrder.first,
                       cur.keyPath == comp.keyPath && cur.order == comp.order {
                        return
                    }
                    sortOrder = [comp]
                }
                .onAppear {
                    sortOrder = [Self.comparator(from: viewModel.sort)]
                }
        }
    }

    private var tableView: some View {
        Table(rows,
              children: \.children,
              selection: $viewModel.selection,
              sortOrder: $sortOrder,
              columnCustomization: $viewModel.columnCustomization) {
            TableColumn("PID", value: \PortTableRow.sortPid) { row in
                Text("\(row.pid)").opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 60, ideal: 70)
            .customizationID("pid")

            TableColumn("Port", value: \PortTableRow.sortPort) { row in
                HStack(spacing: 4) {
                    if row.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(row.portsLabel)
                        .font(.system(.body, design: .monospaced))
                }
                .opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 60, ideal: 80)
            .customizationID("port")

            TableColumn("Process", value: \PortTableRow.sortProcess) { row in
                Text(row.processName).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 100, ideal: 160)
            .customizationID("process")

            TableColumn("Proto", value: \PortTableRow.sortProto) { row in
                Text(row.protoLabel).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 50, ideal: 60)
            .customizationID("proto")

            TableColumn("IP", value: \PortTableRow.sortIP) { row in
                Text(row.ipLabel).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 50, ideal: 60)
            .customizationID("ipFamily")

            TableColumn("Address", value: \PortTableRow.sortAddress) { row in
                Text(row.addressLabel).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 100, ideal: 140)
            .customizationID("address")

            TableColumn("State", value: \PortTableRow.sortState) { row in
                Text(row.stateLabel).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 80, ideal: 100)
            .customizationID("state")

            TableColumn("User", value: \PortTableRow.sortUser) { row in
                Text(row.userLabel).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 80, ideal: 100)
            .customizationID("user")

            TableColumn("Started", value: \PortTableRow.sortStarted) { row in
                Text(row.startedLabel).opacity(row.dimmed ? 0.4 : 1)
            }
            .width(min: 90, ideal: 110)
            .customizationID("started")
        }
        .task {
            // Periodically persist column customization changes (reorder/hide).
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                viewModel.persistCustomization()
            }
        }
    }

    private var columnChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PortColumn.allCases, id: \.self) { col in
                    let isActive = (viewModel.filter.byColumn[col]?.isEmpty == false)
                    Button {
                        openColumn = col
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease").font(.caption2)
                            Text(label(col))
                                .font(.caption)
                                .fontWeight(isActive ? .semibold : .regular)
                            if isActive {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(isActive
                          ? String(localized: "Filter: \(label(col)) (active)")
                          : String(localized: "Filter: \(label(col))"))
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
        case .state:    return Array(Set(viewModel.rawEntries.compactMap { $0.state })).sorted()
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
            // Flat: filter hides non-matching rows (preserves prior behavior).
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

            // Children are sorted explicitly because SwiftUI's hierarchical Table doesn't
            // re-sort rows from its sortOrder binding — the binding only notifies us of
            // header taps. The same applies to top-level ordering below.
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

        // Each multi-value label is reversed only when the user is sorting that very column
        // in descending order. So sorting Port desc flips the port list (and individual
        // ranges) while leaving Proto/IP/State labels alone.
        func ascending(_ column: PortColumn) -> Bool {
            !(sort.column == column && sort.dir == .desc)
        }
        let ports = Set(members.map { $0.port }).sorted()
        let portsLabel = formatPortRanges(ports, ascending: ascending(.port))
        let protoLabel = uniqueSortedJoined(members.map { $0.proto.rawValue }, ascending: ascending(.proto))
        let ipLabel = uniqueSortedJoined(members.map { $0.ipFamily?.rawValue ?? "—" }, ascending: ascending(.ipFamily))
        let addressLabel = uniqueSortedJoined(members.map { $0.localAddress }, ascending: ascending(.address))
        let stateLabel = uniqueSortedJoined(members.map { $0.state ?? "—" }, ascending: ascending(.state))
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

    private static func uniqueSortedJoined(_ values: [String], ascending: Bool = true) -> String {
        var uniq = Array(Set(values)).sorted()
        if !ascending { uniq.reverse() }
        return uniq.joined(separator: ", ")
    }

    /// Compresses sorted ports into ranges: [3000, 3001, 3002, 3005] → "3000-3002, 3005".
    /// When `ascending` is false both the range list and each range's endpoints are flipped
    /// so descending Port sort shows "3005, 3002-3000".
    static func formatPortRanges(_ ports: [UInt16], ascending: Bool = true) -> String {
        guard !ports.isEmpty else { return "" }
        var result: [String] = []
        var start = ports[0]
        var prev = ports[0]
        for p in ports.dropFirst() {
            if p == prev + 1 {
                prev = p
            } else {
                result.append(rangeLabel(start: start, end: prev, ascending: ascending))
                start = p
                prev = p
            }
        }
        result.append(rangeLabel(start: start, end: prev, ascending: ascending))
        if !ascending { result.reverse() }
        return result.joined(separator: ", ")
    }

    private static func rangeLabel(start: UInt16, end: UInt16, ascending: Bool) -> String {
        if start == end { return "\(start)" }
        return ascending ? "\(start)-\(end)" : "\(end)-\(start)"
    }

    // MARK: - Sort helpers

    static func comparator(from spec: SortSpec) -> KeyPathComparator<PortTableRow> {
        let order: SortOrder = spec.dir == .asc ? .forward : .reverse
        switch spec.column {
        case .pid: return KeyPathComparator(\PortTableRow.sortPid, order: order)
        case .port: return KeyPathComparator(\PortTableRow.sortPort, order: order)
        case .process: return KeyPathComparator(\PortTableRow.sortProcess, order: order)
        case .proto: return KeyPathComparator(\PortTableRow.sortProto, order: order)
        case .ipFamily: return KeyPathComparator(\PortTableRow.sortIP, order: order)
        case .address: return KeyPathComparator(\PortTableRow.sortAddress, order: order)
        case .state: return KeyPathComparator(\PortTableRow.sortState, order: order)
        case .user: return KeyPathComparator(\PortTableRow.sortUser, order: order)
        case .started: return KeyPathComparator(\PortTableRow.sortStarted, order: order)
        }
    }

    static func sortSpec(from comparator: KeyPathComparator<PortTableRow>) -> SortSpec {
        let dir: SortDir = comparator.order == .forward ? .asc : .desc
        let column: PortColumn
        switch comparator.keyPath {
        case \PortTableRow.sortPid: column = .pid
        case \PortTableRow.sortPort: column = .port
        case \PortTableRow.sortProcess: column = .process
        case \PortTableRow.sortProto: column = .proto
        case \PortTableRow.sortIP: column = .ipFamily
        case \PortTableRow.sortAddress: column = .address
        case \PortTableRow.sortState: column = .state
        case \PortTableRow.sortUser: column = .user
        case \PortTableRow.sortStarted: column = .started
        default: column = .port
        }
        return SortSpec(column: column, dir: dir)
    }
}
