import SwiftUI

struct PortListTable: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var settings: AppSettings
    @State private var openColumn: PortColumn? = nil
    @State private var sortOrder: [KeyPathComparator<PortEntry>] = [
        KeyPathComparator(\PortEntry.port, order: .forward)
    ]

    /// Pinned ports float to the top; the rest preserve the user's current sort.
    /// When `settings.hideDuplicateRows` is on, rows whose visible columns match are
    /// collapsed to a single entry (lsof reports each socket file descriptor as its
    /// own row, which otherwise surfaces as visual duplicates).
    private var orderedEntries: [PortEntry] {
        let entries = settings.hideDuplicateRows
            ? Self.deduplicated(viewModel.visibleEntries)
            : viewModel.visibleEntries
        let pinned = settings.pinnedPorts
        guard !pinned.isEmpty else { return entries }
        let pins = entries.filter { pinned.contains($0.port) }
        let rest = entries.filter { !pinned.contains($0.port) }
        return pins + rest
    }

    /// Keeps the first occurrence per (pid, port, proto, ipFamily, localAddress, state, user, process) tuple.
    /// The hidden file-descriptor differs across collapsed rows, but those columns are not shown
    /// to the user so they appear identical.
    private static func deduplicated(_ entries: [PortEntry]) -> [PortEntry] {
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

    /// Entry ids whose Process column should be blanked because the row above shares the same PID.
    /// Driven by the "Group same-process rows" setting; pinned rows are excluded so the pin block
    /// always names its owner.
    private var groupedHiddenIds: Set<PortEntry.ID> {
        guard settings.menuBarGroupSamePid else { return [] }
        var hidden: Set<PortEntry.ID> = []
        var prevPid: Int32? = nil
        for e in orderedEntries {
            if settings.pinnedPorts.contains(e.port) {
                prevPid = nil
                continue
            }
            if let p = prevPid, p == e.pid, e.pid > 0 {
                hidden.insert(e.id)
            }
            prevPid = e.pid
        }
        return hidden
    }

    var body: some View {
        VStack(spacing: 0) {
            columnChips
            tableView
            .onChange(of: sortOrder) { _, new in
                if let first = new.first {
                    viewModel.sort = SortSpec.fromComparator(first)
                }
            }
            .onChange(of: viewModel.sort) { _, new in
                let comp = new.toComparator()
                if let cur = sortOrder.first,
                   cur.keyPath == comp.keyPath && cur.order == comp.order {
                    return
                }
                sortOrder = [comp]
            }
            .onAppear {
                sortOrder = [viewModel.sort.toComparator()]
            }
        }
    }

    private var tableView: some View {
        Table(orderedEntries,
              selection: $viewModel.selection,
              sortOrder: $sortOrder,
              columnCustomization: $viewModel.columnCustomization) {
            TableColumn("PID", value: \PortEntry.pid) { e in Text("\(e.pid)") }
                .width(min: 60, ideal: 70)
                .customizationID("pid")
            TableColumn("Port", value: \PortEntry.port) { e in
                HStack(spacing: 4) {
                    if settings.pinnedPorts.contains(e.port) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("\(e.port)")
                }
            }
                .width(min: 60, ideal: 80)
                .customizationID("port")
            TableColumn("Process", value: \PortEntry.processName) { e in
                Text(groupedHiddenIds.contains(e.id) ? "" : e.processName)
            }
                .width(min: 100, ideal: 160)
                .customizationID("process")
            TableColumn("Proto", value: \PortEntry.proto.rawValue) { e in Text(e.proto.rawValue) }
                .width(min: 50, ideal: 60)
                .customizationID("proto")
            TableColumn("IP", value: \PortEntry.ipFamilyForSort) { e in Text(e.ipFamily?.rawValue ?? "—") }
                .width(min: 50, ideal: 60)
                .customizationID("ipFamily")
            TableColumn("Address", value: \PortEntry.localAddress) { e in Text(e.localAddress) }
                .width(min: 100, ideal: 140)
                .customizationID("address")
            TableColumn("State", value: \PortEntry.stateForSort) { e in Text(e.state ?? "—") }
                .width(min: 80, ideal: 100)
                .customizationID("state")
            TableColumn("User", value: \PortEntry.user) { e in Text(e.user) }
                .width(min: 80, ideal: 100)
                .customizationID("user")
            TableColumn("Started", value: \PortEntry.startedForSort) { (e: PortEntry) -> Text in
                if let st = e.startTime {
                    return Text(st, format: .dateTime.hour().minute().day().month())
                }
                return Text("—")
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
}
