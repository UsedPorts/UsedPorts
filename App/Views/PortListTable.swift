import SwiftUI

struct PortListTable: View {
    @ObservedObject var viewModel: PortListViewModel
    @State private var openColumn: PortColumn? = nil
    @State private var sortOrder: [KeyPathComparator<PortEntry>] = [
        KeyPathComparator(\PortEntry.port, order: .forward)
    ]

    var body: some View {
        VStack(spacing: 0) {
            columnChips
            Table(viewModel.visibleEntries, selection: $viewModel.selection, sortOrder: $sortOrder) {
                TableColumn("PID", value: \PortEntry.pid) { e in Text("\(e.pid)") }
                    .width(min: 60, ideal: 70)
                TableColumn("Port", value: \PortEntry.port) { e in Text("\(e.port)") }
                    .width(min: 60, ideal: 70)
                TableColumn("Proto", value: \PortEntry.proto.rawValue) { e in Text(e.proto.rawValue) }
                    .width(min: 50, ideal: 60)
                TableColumn("Process", value: \PortEntry.processName) { e in Text(e.processName) }
                    .width(min: 100, ideal: 160)
                TableColumn("Address", value: \PortEntry.localAddress) { e in Text(e.localAddress) }
                    .width(min: 100, ideal: 140)
                TableColumn("State", value: \PortEntry.stateForSort) { e in Text(e.state ?? "—") }
                    .width(min: 80, ideal: 100)
                TableColumn("User", value: \PortEntry.user) { e in Text(e.user) }
                    .width(min: 80, ideal: 100)
                TableColumn("Started", value: \PortEntry.startedForSort) { (e: PortEntry) -> Text in
                    if let st = e.startTime {
                        return Text(st, format: .dateTime.hour().minute().day().month())
                    }
                    return Text("—")
                }
                .width(min: 90, ideal: 110)
            }
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

    private var columnChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PortColumn.allCases, id: \.self) { col in
                    Button {
                        openColumn = col
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "line.3.horizontal.decrease.circle").font(.caption2)
                            Text(label(col)).font(.caption)
                            if viewModel.filter.byColumn[col]?.isEmpty == false {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .foregroundStyle(.tint)
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .help("필터: \(label(col))")
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
        case .process: return "Process"
        case .address: return "Address"
        case .state: return "State"
        case .user: return "User"
        case .started: return "Started"
        }
    }

    private func dynamicValues(for c: PortColumn) -> [String] {
        switch c {
        case .address: return Array(Set(viewModel.rawEntries.map { $0.localAddress })).sorted()
        case .state:   return Array(Set(viewModel.rawEntries.compactMap { $0.state })).sorted()
        case .user:    return Array(Set(viewModel.rawEntries.map { $0.user })).sorted()
        default:       return []
        }
    }
}
