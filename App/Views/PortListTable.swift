import SwiftUI

struct PortListTable: View {
    @ObservedObject var viewModel: PortListViewModel

    var body: some View {
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
