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
    @State private var compoundText: String = ""
    @State private var compoundSelected: Set<String> = []
    @State private var tspec: TimeRangeSpec = TimeRangeSpec()
    @State private var lastNText: String = ""
    @State private var didHydrate: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterRow
            Divider()
            HStack {
                Button(role: .destructive) {
                    viewModel.filter.byColumn.removeValue(forKey: column)
                    clearLocalState()
                } label: {
                    Label("Clear filter", systemImage: "trash")
                }
                .disabled(viewModel.filter.byColumn[column] == nil)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: column == .started ? 420 : 280)
        .onAppear(perform: hydrate)
    }

    private static let hour24Locale: Locale = {
        var components = Locale.Components(locale: Locale.current)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }()

    private func clearLocalState() {
        numberInput = ""
        textInput = ""
        useRegex = false
        selected = []
        compoundText = ""
        compoundSelected = []
        tspec = TimeRangeSpec()
        lastNText = ""
    }

    private func hydrate() {
        // First-load guard: hydrate only once while the popover instance is alive.
        // Prevents overwriting user input if an external publish occurs while typing.
        if didHydrate { return }
        didHydrate = true
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
            // Legacy compatibility: display as a fixed range.
            tspec = TimeRangeSpec(mode: .customFixed, fromDate: from, toDate: to)
        case .compound(let sel, let t):
            compoundSelected = sel
            compoundText = t
        case .timeSpec(let s):
            tspec = s
            if let n = s.lastN { lastNText = "\(n)" }
        case .none:
            break
        }
        if column == .started && tspec.mode == .customFixed {
            let now = Date()
            if tspec.fromDate == nil { tspec.fromDate = now }
            if tspec.toDate == nil { tspec.toDate = now }
        }
    }

    @ViewBuilder
    private var filterRow: some View {
        switch column {
        case .pid, .port:
            numberFilter
        case .proto:
            compoundFilter(placeholder: "TCP, UDP", options: ["TCP", "UDP"], collapsible: false)
        case .ipFamily:
            compoundFilter(placeholder: "IPv4, IPv6", options: ["IPv4", "IPv6"], collapsible: false)
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

    // MARK: - Shared clear button
    @ViewBuilder
    private func clearButton(visible: Bool, action: @escaping () -> Void) -> some View {
        if visible {
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear input")
        }
    }

    @ViewBuilder
    private func compoundFilter(placeholder: String, options: [String], collapsible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter (comma separated, partial match)").font(.caption)
            HStack(spacing: 4) {
                TextField(placeholder, text: $compoundText, onCommit: applyCompound)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: compoundText) { _, _ in applyCompound() }
                clearButton(visible: !compoundText.isEmpty) {
                    compoundText = ""
                    applyCompound()
                }
            }
            if !options.isEmpty {
                Divider()
                if collapsible {
                    DisclosureGroup(String(localized: "Discovered values (\(options.count))")) {
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
        let label: String
        if opt.isEmpty {
            label = (column == .state) ? "—" : "(empty)"
        } else {
            label = opt
        }
        return Toggle(label, isOn: Binding(
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

    private var numberFilter: some View {
        VStack(alignment: .leading) {
            Text("3000  ·  1000~2000  ·  5000+  ·  ~80").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("e.g. 3000, 1000~2000, 5000+", text: $numberInput, onCommit: applyNumber)
                    .textFieldStyle(.roundedBorder)
                    // Apply immediately on every keystroke — works without an Apply button or onCommit.
                    .onChange(of: numberInput) { _, _ in applyNumber() }
                clearButton(visible: !numberInput.isEmpty) {
                    numberInput = ""
                    applyNumber()
                }
            }
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
            HStack(spacing: 4) {
                TextField("Text or regex", text: $textInput, onCommit: applyText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: textInput) { _, _ in applyText() }
                clearButton(visible: !textInput.isEmpty) {
                    textInput = ""
                    applyText()
                }
            }
            Toggle("Regex", isOn: $useRegex)
                .onChange(of: useRegex) { _, _ in applyText() }
        }
    }

    private var addressTextFilter: some View {
        VStack(alignment: .leading) {
            Text("Filter (IP/CIDR, comma separated)").font(.caption)
            HStack(spacing: 4) {
                TextField(
                    "e.g. 127.0.0.1, 192.168.1.0/24, ::1",
                    text: $textInput,
                    onCommit: applyAddressText
                )
                .textFieldStyle(.roundedBorder)
                clearButton(visible: !textInput.isEmpty) {
                    textInput = ""
                    applyAddressText()
                }
            }
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

    private var timeRangeFilter: some View {
        VStack(alignment: .leading) {
            Picker("Preset", selection: $tspec.mode) {
                Text("Any").tag(TimeRangeSpec.Mode.any)
                Text("Last 5 min").tag(TimeRangeSpec.Mode.last5m)
                Text("Last 1 hour").tag(TimeRangeSpec.Mode.last1h)
                Text("Today").tag(TimeRangeSpec.Mode.today)
                Text("Custom (Fixed)").tag(TimeRangeSpec.Mode.customFixed)
                Text("Custom (Last)").tag(TimeRangeSpec.Mode.customLast)
            }
            .onChange(of: tspec.mode) { _, newMode in
                if newMode == .customFixed {
                    let now = Date()
                    if tspec.fromDate == nil { tspec.fromDate = now }
                    if tspec.toDate == nil { tspec.toDate = now }
                }
                applyTimeSpec()
            }
            if tspec.mode == .customFixed {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow(alignment: .center) {
                        Text("From")
                        nullableDateTimeCell(
                            date: Binding(
                                get: { tspec.fromDate },
                                set: { tspec.fromDate = $0; applyTimeSpec() }
                            ),
                            placeholder: String(localized: "Any start")
                        )
                    }
                    GridRow(alignment: .center) {
                        Text("To")
                        nullableDateTimeCell(
                            date: Binding(
                                get: { tspec.toDate },
                                set: { tspec.toDate = $0; applyTimeSpec() }
                            ),
                            placeholder: String(localized: "Any end")
                        )
                    }
                }
            }
            if tspec.mode == .customLast {
                HStack {
                    Text("Last")
                    TextField("N", text: $lastNText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: lastNText) { _, _ in applyTimeSpec() }
                    Picker("", selection: Binding(
                        get: { tspec.lastUnit ?? "min" },
                        set: { tspec.lastUnit = $0; applyTimeSpec() })) {
                        Text("min").tag("min")
                        Text("hour").tag("hour")
                        Text("day").tag("day")
                    }
                    .frame(width: 90)
                }
            }
        }
    }

    @ViewBuilder
    private func nullableDateTimeCell(date: Binding<Date?>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            if let current = date.wrappedValue {
                let dateBinding = Binding<Date>(
                    get: { current },
                    set: { date.wrappedValue = $0 }
                )
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Self.hour24Locale)
            } else {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Button {
                date.wrappedValue = Date()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Reset to now"))
            Button {
                date.wrappedValue = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Clear"))
        }
    }

    private func applyTimeSpec() {
        if tspec.mode == .customLast {
            tspec.lastN = Int(lastNText.trimmingCharacters(in: .whitespaces))
        }
        if tspec.isEmpty || tspec.mode == .any {
            viewModel.filter.byColumn.removeValue(forKey: column)
        } else {
            viewModel.filter.byColumn[column] = .timeSpec(tspec)
        }
    }
}
