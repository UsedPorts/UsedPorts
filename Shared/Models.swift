import Foundation

public enum NetProto: String, Codable, CaseIterable, Hashable {
    case tcp = "TCP"
    case udp = "UDP"
}

public struct PortEntry: Identifiable, Hashable, Codable {
    public let id: String
    public let pid: Int32
    public let processName: String
    public let user: String
    public let proto: NetProto
    public let localAddress: String
    public let port: UInt16
    public let state: String?

    public var executablePath: String?
    public var cwd: String?
    public var startTime: Date?

    public init(
        id: String,
        pid: Int32,
        processName: String,
        user: String,
        proto: NetProto,
        localAddress: String,
        port: UInt16,
        state: String?,
        executablePath: String? = nil,
        cwd: String? = nil,
        startTime: Date? = nil
    ) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.user = user
        self.proto = proto
        self.localAddress = localAddress
        self.port = port
        self.state = state
        self.executablePath = executablePath
        self.cwd = cwd
        self.startTime = startTime
    }
}

public extension PortEntry {
    /// Sort-key helpers that turn optionals into stable, Comparable strings/dates.
    var stateForSort: String { state ?? "" }
    var startedForSort: Date { startTime ?? .distantPast }
}

public enum PortColumn: String, CaseIterable, Hashable, Codable {
    case pid, port, proto, process, address, state, user, started
}

public enum SortDir: String, Codable { case asc, desc }
public struct SortSpec: Hashable, Codable {
    public var column: PortColumn
    public var dir: SortDir
    public init(column: PortColumn, dir: SortDir) {
        self.column = column; self.dir = dir
    }
}

public extension SortSpec {
    func toComparator() -> KeyPathComparator<PortEntry> {
        let order: SortOrder = (dir == .asc) ? .forward : .reverse
        switch column {
        case .pid:     return KeyPathComparator(\PortEntry.pid, order: order)
        case .port:    return KeyPathComparator(\PortEntry.port, order: order)
        case .proto:   return KeyPathComparator(\PortEntry.proto.rawValue, order: order)
        case .ipFamily:  return KeyPathComparator(\PortEntry.ipFamilyForSort, order: order)
        case .process: return KeyPathComparator(\PortEntry.processName, order: order)
        case .address: return KeyPathComparator(\PortEntry.localAddress, order: order)
        case .state:   return KeyPathComparator(\PortEntry.stateForSort, order: order)
        case .user:    return KeyPathComparator(\PortEntry.user, order: order)
        case .started: return KeyPathComparator(\PortEntry.startedForSort, order: order)
        }
    }

    static func fromComparator(_ c: KeyPathComparator<PortEntry>) -> SortSpec {
        let dir: SortDir = (c.order == .forward) ? .asc : .desc
        let kp = c.keyPath
        let column: PortColumn
        switch kp {
        case \PortEntry.pid:                column = .pid
        case \PortEntry.port:               column = .port
        case \PortEntry.proto.rawValue:     column = .proto
        case \PortEntry.ipFamilyForSort:      column = .ipFamily
        case \PortEntry.processName:        column = .process
        case \PortEntry.localAddress:       column = .address
        case \PortEntry.stateForSort:       column = .state
        case \PortEntry.user:               column = .user
        case \PortEntry.startedForSort:     column = .started
        default:                            column = .port
        }
        return SortSpec(column: column, dir: dir)
    }
}

/// Filter spec for numeric columns (PID/Port).
public struct NumberSpec: Hashable, Codable {
    public var exact: Set<Int> = []
    public var ranges: [ClosedRange<Int>] = []

    public init(exact: Set<Int> = [], ranges: [ClosedRange<Int>] = []) {
        self.exact = exact; self.ranges = ranges
    }

    public func matches(_ value: Int) -> Bool {
        if exact.contains(value) { return true }
        for r in ranges where r.contains(value) { return true }
        return exact.isEmpty && ranges.isEmpty
    }

    public var isEmpty: Bool { exact.isEmpty && ranges.isEmpty }

    /// Parses a user input string. e.g. "3000", "1000-2000", "3000,5432,8080-8090".
    /// Invalid tokens are ignored.
    public static func parse(_ text: String) -> NumberSpec {
        var exact = Set<Int>()
        var ranges: [ClosedRange<Int>] = []
        let tokens = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        for token in tokens {
            if let dash = token.firstIndex(of: "-") {
                let lhs = String(token[..<dash])
                let rhs = String(token[token.index(after: dash)...])
                if let a = Int(lhs), let b = Int(rhs), a <= b {
                    ranges.append(a...b)
                }
            } else if let n = Int(token) {
                exact.insert(n)
            }
        }
        return NumberSpec(exact: exact, ranges: ranges)
    }
}

public enum ColumnFilter: Hashable, Codable {
    case number(NumberSpec)
    case multiSelect(Set<String>)
    case text(String, regex: Bool)
    case timeRange(Date?, Date?)

    public var isEmpty: Bool {
        switch self {
        case .number(let s): return s.isEmpty
        case .multiSelect(let s): return s.isEmpty
        case .text(let t, _): return t.isEmpty
        case .timeRange(let a, let b): return a == nil && b == nil
        }
    }
}

public struct FilterState: Hashable, Codable {
    public var globalSearch: String = ""
    public var byColumn: [PortColumn: ColumnFilter] = [:]
    public init() {}
}
