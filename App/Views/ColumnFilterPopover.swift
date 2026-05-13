import SwiftUI

struct ColumnFilterPopover: View {
    let column: PortColumn
    let availableValues: [String]
    @ObservedObject var viewModel: PortListViewModel
    @Binding var isPresented: Bool

    @State private var numberInput: String = ""
    @State private var textInput: String = ""
    @State private var useRegex: Bool = false
    @State private var selected: Set<String> = []
    @State private var fromDate: Date = Date()
    @State private var toDate: Date = Date()
    @State private var preset: String = "any"
    @State private var compoundText: String = ""
    @State private var compoundSelected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterRow
            Divider()
            HStack {
                Button("Clear") {
                    viewModel.filter.byColumn.removeValue(forKey: column)
                    numberInput = ""
                    textInput = ""
                    selected = []
                    preset = "any"
                    compoundText = ""
                    compoundSelected = []
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        switch viewModel.filter.byColumn[column] {
        case .number(let s):
            let parts = s.exact.map(String.init) + s.ranges.map { "\($0.lowerBound)-\($0.upperBound)" }
            numberInput = parts.joined(separator: ",")
        case .text(let t, let r):
            textInput = t
            useRegex = r
            compoundText = t
        case .multiSelect(let s):
            selected = s
            compoundSelected = s
        case .timeRange(let from, let to):
            if let from { fromDate = from }
            if let to { toDate = to }
            preset = "custom"
        case .compound(let sel, let t):
            compoundSelected = sel
            compoundText = t
        case .none:
            break
        }
    }

    @ViewBuilder
    private var filterRow: some View {
        switch column {
        case .pid, .port:
            numberFilter
        case .proto:
            compoundFilter(placeholder: "TCP, UDP", options: ["TCP", "UDP"], collapsible: false)
        case .process:
            textFilter
        case .address:
            compoundFilter(
                placeholder: "127.0.0.1, 192.168.1.0/24, ::1",
                options: availableValues,
                collapsible: true
            )
        case .state:
            compoundFilter(
                placeholder: "LISTEN, ESTABLISHED",
                options: availableValues,
                collapsible: false
            )
        case .user:
            compoundFilter(
                placeholder: "name, _postgres",
                options: availableValues,
                collapsible: false
            )
        case .started:
            timeRangeFilter
        }
    }

    @ViewBuilder
    private func compoundFilter(placeholder: String, options: [String], collapsible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter (comma separated, partial match)").font(.caption)
            TextField(placeholder, text: $compoundText, onCommit: applyCompound)
                .textFieldStyle(.roundedBorder)
            Button("Apply") { applyCompound() }
            if !options.isEmpty {
                Divider()
                if collapsible {
                    DisclosureGroup("발견된 값 (\(options.count))") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(options, id: \.self) { opt in
                                    compoundCheckboxRow(opt)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(options, id: \.self) { opt in
                            compoundCheckboxRow(opt)
                        }
                    }
                }
            }
        }
    }

    private func compoundCheckboxRow(_ opt: String) -> some View {
        Toggle(opt.isEmpty ? "(empty)" : opt, isOn: Binding(
            get: { compoundSelected.contains(opt) },
            set: { on in
                if on { compoundSelected.insert(opt) } else { compoundSelected.remove(opt) }
                applyCompound()
            }
        ))
    }

    private func applyCompound() {
        let trimmed = compoundText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && compoundSelected.isEmpty {
            viewModel.filter.byColumn.removeValue(forKey: column)
        } else {
            viewModel.filter.byColumn[column] = .compound(selected: compoundSelected, text: trimmed)
        }
    }

    private func tokenTextFilter(placeholder: String) -> some View {
        VStack(alignment: .leading) {
            Text("Filter (comma separated, partial match)").font(.caption)
            TextField(placeholder, text: $textInput, onCommit: applyTokenText)
                .textFieldStyle(.roundedBorder)
            Button("Apply") { applyTokenText() }
        }
        .onAppear {
            if case .text(let t, _) = viewModel.filter.byColumn[column] {
                textInput = t
            }
        }
    }

    private func applyTokenText() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            viewModel.filter.byColumn.removeValue(forKey: column)
        } else {
            viewModel.filter.byColumn[column] = .text(trimmed, regex: false)
        }
    }

    private var numberFilter: some View {
        VStack(alignment: .leading) {
            Text("Filter (e.g. 3000, 1000-2000, 8080,9000)").font(.caption)
            TextField("", text: $numberInput, onCommit: applyNumber)
                .textFieldStyle(.roundedBorder)
            Button("Apply") { applyNumber() }
        }
    }

    private func applyNumber() {
        let spec = NumberSpec.parse(numberInput)
        if spec.isEmpty {
            viewModel.filter.byColumn.removeValue(forKey: column)
        } else {
            viewModel.filter.byColumn[column] = .number(spec)
        }
    }

    private var textFilter: some View {
        VStack(alignment: .leading) {
            TextField("Text or regex", text: $textInput, onCommit: applyText)
                .textFieldStyle(.roundedBorder)
            Toggle("Regex", isOn: $useRegex)
            Button("Apply") { applyText() }
        }
    }

    private var addressTextFilter: some View {
        VStack(alignment: .leading) {
            Text("Filter (IP/CIDR, comma separated)").font(.caption)
            TextField(
                "e.g. 127.0.0.1, 192.168.1.0/24, ::1",
                text: $textInput,
                onCommit: applyAddressText
            )
            .textFieldStyle(.roundedBorder)
            Button("Apply") { applyAddressText() }
        }
    }

    private func applyAddressText() {
        if textInput.isEmpty {
            viewModel.filter.byColumn.removeValue(forKey: column)
        } else {
            viewModel.filter.byColumn[column] = .text(textInput, regex: false)
        }
    }

    private func applyText() {
        if textInput.isEmpty {
            viewModel.filter.byColumn.removeValue(forKey: column)
        } else {
            viewModel.filter.byColumn[column] = .text(textInput, regex: useRegex)
        }
    }

    private func multiSelectFilter(options: [String]) -> some View {
        VStack(alignment: .leading) {
            ForEach(options, id: \.self) { opt in
                Toggle(opt, isOn: Binding(
                    get: { selected.contains(opt) },
                    set: { on in
                        if on { selected.insert(opt) } else { selected.remove(opt) }
                        if selected.isEmpty {
                            viewModel.filter.byColumn.removeValue(forKey: column)
                        } else {
                            viewModel.filter.byColumn[column] = .multiSelect(selected)
                        }
                    }
                ))
            }
        }
    }

    private var timeRangeFilter: some View {
        VStack(alignment: .leading) {
            Picker("Preset", selection: $preset) {
                Text("Any").tag("any")
                Text("Last 5 min").tag("5m")
                Text("Last 1 hour").tag("1h")
                Text("Today").tag("today")
                Text("Custom").tag("custom")
            }
            if preset == "custom" {
                DatePicker("From", selection: $fromDate)
                DatePicker("To", selection: $toDate)
            }
            Button("Apply") { applyTime() }
        }
    }

    private func applyTime() {
        switch preset {
        case "any":
            viewModel.filter.byColumn.removeValue(forKey: column)
        case "5m":
            viewModel.filter.byColumn[column] = .timeRange(Date().addingTimeInterval(-300), nil)
        case "1h":
            viewModel.filter.byColumn[column] = .timeRange(Date().addingTimeInterval(-3600), nil)
        case "today":
            let start = Calendar.current.startOfDay(for: Date())
            viewModel.filter.byColumn[column] = .timeRange(start, nil)
        case "custom":
            viewModel.filter.byColumn[column] = .timeRange(fromDate, toDate)
        default:
            break
        }
    }
}
