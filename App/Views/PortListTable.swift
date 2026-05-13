import SwiftUI

struct PortListTable: View {
    @ObservedObject var viewModel: PortListViewModel
    @State private var openColumn: PortColumn? = nil

    var body: some View {
        VStack(spacing: 0) {
            columnChips
            Table(viewModel.visibleEntries, selection: $viewModel.selection) {
                TableColumn("PID")     { Text("\($0.pid)") }.width(min: 60, ideal: 70)
                TableColumn("Port")    { Text("\($0.port)") }.width(min: 60, ideal: 70)
                TableColumn("Proto")   { Text($0.proto.rawValue) }.width(min: 50, ideal: 60)
                TableColumn("Process") { Text($0.processName) }.width(min: 100, ideal: 160)
                TableColumn("Address") { Text($0.localAddress) }.width(min: 100, ideal: 140)
                TableColumn("State")   { Text($0.state ?? "—") }.width(min: 80, ideal: 100)
                TableColumn("User")    { Text($0.user) }.width(min: 80, ideal: 100)
                TableColumn("Started") { (e: PortEntry) -> Text in
                    if let st = e.startTime {
                        return Text(st, format: .dateTime.hour().minute().day().month())
                    }
                    return Text("—")
                }
                .width(min: 90, ideal: 110)
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
                            Text(label(col)).font(.caption)
                            Image(systemName: "chevron.down").font(.caption2)
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
