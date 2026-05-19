import AppKit
import SwiftUI

/// Stable identity wrapper for `PortTableRow`. NSOutlineView relies on items being
/// pointer-equal across reload cycles, so the coordinator keeps a single instance per
/// `row.id` and just refreshes its payload.
final class PortRowItem: NSObject {
    var row: PortTableRow
    init(_ row: PortTableRow) { self.row = row }
}

/// NSOutlineView-backed table for the main port list. Wraps a native NSOutlineView so
/// row-level selection styling — including children that appear after a disclosure
/// expands — Just Works, which SwiftUI's hierarchical Table can't deliver on macOS.
struct PortOutlineView: NSViewRepresentable {
    let rows: [PortTableRow]
    @Binding var selection: Set<PortEntry.ID>
    @Binding var sort: SortSpec
    @Binding var expandedGroups: Set<Int32>

    // MARK: - Lifecycle

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.style = .inset
        outline.allowsMultipleSelection = true
        outline.allowsColumnReordering = true
        outline.allowsColumnResizing = true
        outline.usesAlternatingRowBackgroundColors = false
        outline.rowSizeStyle = .default
        outline.autosaveExpandedItems = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator

        for spec in PortOutlineColumn.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.title = spec.title
            column.minWidth = spec.minWidth
            column.width = spec.idealWidth
            column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: true)
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        context.coordinator.applySortDescriptors(on: outline)

        context.coordinator.outlineView = outline
        context.coordinator.refresh(rows: rows, animated: false)
        context.coordinator.applyExpansionState()
        context.coordinator.applySelection()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = outline
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let outline = scroll.documentView as? NSOutlineView else { return }
        context.coordinator.outlineView = outline
        context.coordinator.parent = self
        context.coordinator.applySortDescriptors(on: outline)
        context.coordinator.refresh(rows: rows, animated: true)
        context.coordinator.applyExpansionState()
        context.coordinator.applySelection()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        fileprivate weak var outlineView: NSOutlineView?
        fileprivate var parent: PortOutlineView
        private var itemsById: [String: PortRowItem] = [:]
        private var topLevelItems: [PortRowItem] = []
        /// Reentrancy guard so applying selection/expansion/sort programmatically doesn't
        /// echo back through delegate callbacks and tear up the bindings.
        private var isApplyingExternalState = false

        init(parent: PortOutlineView) {
            self.parent = parent
        }

        // MARK: - Refresh

        func refresh(rows: [PortTableRow], animated: Bool) {
            guard let outline = outlineView else { return }
            var nextIds: Set<String> = []
            func register(_ row: PortTableRow) {
                nextIds.insert(row.id)
                let item = itemForRow(row)
                item.row = row
                row.children?.forEach(register)
            }
            rows.forEach(register)

            itemsById = itemsById.filter { nextIds.contains($0.key) }
            topLevelItems = rows.map { itemForRow($0) }

            isApplyingExternalState = true
            outline.reloadData()
            isApplyingExternalState = false
        }

        func itemForRow(_ row: PortTableRow) -> PortRowItem {
            if let existing = itemsById[row.id] { return existing }
            let item = PortRowItem(row)
            itemsById[row.id] = item
            return item
        }

        // MARK: - Selection sync

        func applySelection() {
            guard let outline = outlineView else { return }
            var indexes = IndexSet()
            for id in parent.selection {
                guard let item = itemsById[id] else { continue }
                let row = outline.row(forItem: item)
                if row >= 0 { indexes.insert(row) }
            }
            if outline.selectedRowIndexes != indexes {
                isApplyingExternalState = true
                outline.selectRowIndexes(indexes, byExtendingSelection: false)
                isApplyingExternalState = false
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingExternalState, let outline = outlineView else { return }
            var newSelection: Set<PortEntry.ID> = []
            for row in outline.selectedRowIndexes {
                if let item = outline.item(atRow: row) as? PortRowItem {
                    newSelection.insert(item.row.id)
                }
            }
            if newSelection != parent.selection {
                parent.selection = newSelection
            }
        }

        // MARK: - Expansion sync

        func applyExpansionState() {
            guard let outline = outlineView else { return }
            for item in itemsById.values {
                guard item.row.children != nil else { continue }
                let shouldExpand = parent.expandedGroups.contains(item.row.pid)
                let isExpanded = outline.isItemExpanded(item)
                if shouldExpand != isExpanded {
                    isApplyingExternalState = true
                    if shouldExpand { outline.expandItem(item) } else { outline.collapseItem(item) }
                    isApplyingExternalState = false
                }
            }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isApplyingExternalState,
                  let item = notification.userInfo?["NSObject"] as? PortRowItem else { return }
            if !parent.expandedGroups.contains(item.row.pid) {
                parent.expandedGroups.insert(item.row.pid)
            }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isApplyingExternalState,
                  let item = notification.userInfo?["NSObject"] as? PortRowItem else { return }
            if parent.expandedGroups.contains(item.row.pid) {
                parent.expandedGroups.remove(item.row.pid)
            }
        }

        // MARK: - Sort sync

        func applySortDescriptors(on outline: NSOutlineView) {
            guard let col = PortOutlineColumn(portColumn: parent.sort.column) else { return }
            let descriptor = NSSortDescriptor(key: col.id, ascending: parent.sort.dir == .asc)
            if outline.sortDescriptors.first?.key != descriptor.key
                || outline.sortDescriptors.first?.ascending != descriptor.ascending {
                isApplyingExternalState = true
                outline.sortDescriptors = [descriptor]
                isApplyingExternalState = false
            }
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplyingExternalState,
                  let descriptor = outlineView.sortDescriptors.first,
                  let key = descriptor.key,
                  let col = PortOutlineColumn(rawValue: key) else { return }
            let spec = SortSpec(column: col.toPortColumn(), dir: descriptor.ascending ? .asc : .desc)
            if parent.sort != spec { parent.sort = spec }
        }

        // MARK: - DataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil { return topLevelItems.count }
            guard let item = item as? PortRowItem else { return 0 }
            return item.row.children?.count ?? 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil { return topLevelItems[index] }
            let parent = item as! PortRowItem
            let childRow = parent.row.children![index]
            return itemForRow(childRow)
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? PortRowItem else { return false }
            return (item.row.children?.isEmpty == false)
        }

        // MARK: - Delegate (cell views)

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? PortRowItem,
                  let columnId = tableColumn?.identifier.rawValue,
                  let spec = PortOutlineColumn(rawValue: columnId) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("port-cell-\(spec.id)")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? HostingCell)
                ?? HostingCell(identifier: identifier)
            cell.update(row: item.row, column: spec)
            return cell
        }
    }
}

// MARK: - Cell view

/// NSTableCellView hosting a SwiftUI view so we keep pin icons / monospaced port labels /
/// dim opacity consistent with the rest of the app.
private final class HostingCell: NSTableCellView {
    private let host: NSHostingView<PortOutlineCellContent>

    init(identifier: NSUserInterfaceItemIdentifier) {
        host = NSHostingView(rootView: PortOutlineCellContent(row: .placeholder, column: .pid))
        super.init(frame: .zero)
        self.identifier = identifier
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(row: PortTableRow, column: PortOutlineColumn) {
        host.rootView = PortOutlineCellContent(row: row, column: column)
    }
}

private struct PortOutlineCellContent: View {
    let row: PortTableRow
    let column: PortOutlineColumn

    var body: some View {
        HStack(spacing: 4) {
            if column == .port, row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(column.text(for: row))
                .font(column == .port
                      ? .system(.body, design: .monospaced)
                      : .body)
                .opacity(row.dimmed ? 0.4 : 1)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Column definitions

enum PortOutlineColumn: String, CaseIterable {
    case pid
    case port
    case process
    case proto
    case ipFamily
    case address
    case state
    case user
    case started

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pid: return "PID"
        case .port: return "Port"
        case .process: return "Process"
        case .proto: return "Proto"
        case .ipFamily: return "IP"
        case .address: return "Address"
        case .state: return "State"
        case .user: return "User"
        case .started: return "Started"
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .pid, .port, .proto, .ipFamily: return 50
        case .process, .state: return 80
        case .address: return 100
        case .user: return 80
        case .started: return 90
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .pid: return 70
        case .port: return 80
        case .process: return 160
        case .proto, .ipFamily: return 60
        case .address: return 140
        case .state: return 100
        case .user: return 100
        case .started: return 110
        }
    }

    func text(for row: PortTableRow) -> String {
        switch self {
        case .pid: return "\(row.pid)"
        case .port: return row.portsLabel
        case .process: return row.processName
        case .proto: return row.protoLabel
        case .ipFamily: return row.ipLabel
        case .address: return row.addressLabel
        case .state: return row.stateLabel
        case .user: return row.userLabel
        case .started: return row.startedLabel
        }
    }

    func toPortColumn() -> PortColumn {
        switch self {
        case .pid: return .pid
        case .port: return .port
        case .process: return .process
        case .proto: return .proto
        case .ipFamily: return .ipFamily
        case .address: return .address
        case .state: return .state
        case .user: return .user
        case .started: return .started
        }
    }

    init?(portColumn: PortColumn) {
        switch portColumn {
        case .pid: self = .pid
        case .port: self = .port
        case .process: self = .process
        case .proto: self = .proto
        case .ipFamily: self = .ipFamily
        case .address: self = .address
        case .state: self = .state
        case .user: self = .user
        case .started: self = .started
        }
    }
}

private extension PortTableRow {
    /// Dummy row used to seed the hosting view's initial root view. Replaced on first
    /// update; never displayed.
    static var placeholder: PortTableRow {
        let key = RowSortKey(primary: "", tieBreaker: 0)
        return PortTableRow(
            id: "__placeholder__",
            kind: .leaf,
            pid: 0,
            processName: "",
            portsLabel: "",
            protoLabel: "",
            ipLabel: "",
            addressLabel: "",
            stateLabel: "",
            userLabel: "",
            startedLabel: "",
            dimmed: false,
            isPinned: false,
            sortPid: key,
            sortPort: key,
            sortProcess: key,
            sortProto: key,
            sortIP: key,
            sortAddress: key,
            sortState: key,
            sortUser: key,
            sortStarted: key,
            children: nil,
            backingEntries: []
        )
    }
}
