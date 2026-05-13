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

    /// Parses a user input string.
    /// Supported syntax (comma- or whitespace-separated):
    ///   `3000`              → exact value
    ///   `1000-2000`         → range (same as a~b)
    ///   `1000~2000`         → range
    ///   `3000+`             → 3000 or above
    ///   `3000~` / `3000-`   → 3000 or above (open-ended right)
    ///   `~3000` / `-3000`   → 3000 or below (open-ended left, from 0)
    /// Invalid tokens are ignored.
    public static func parse(_ text: String) -> NumberSpec {
        var exact = Set<Int>()
        var ranges: [ClosedRange<Int>] = []
        let tokens = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        for token in tokens {
            let str = String(token)
            // `N+` suffix → N or above
            if str.hasSuffix("+"), let n = Int(str.dropLast()) {
                ranges.append(n...Int.max)
                continue
            }
            // `-` or `~` range separator
            let sep = str.firstIndex(where: { $0 == "-" || $0 == "~" })
            if let sep {
                let lhs = String(str[..<sep])
                let rhs = String(str[str.index(after: sep)...])
                let lhsN = Int(lhs)
                let rhsN = Int(rhs)
                if let a = lhsN, let b = rhsN, a <= b {
                    ranges.append(a...b)
                } else if let a = lhsN, rhs.isEmpty {
                    ranges.append(a...Int.max)             // `N~` / `N-`
                } else if let b = rhsN, lhs.isEmpty {
                    ranges.append(0...b)                    // `~N` / `-N`
                }
                continue
            }
            if let n = Int(str) {
                exact.insert(n)
            }
        }
        return NumberSpec(exact: exact, ranges: ranges)
    }
}

/// Time-range filter spec for the Started column.
/// Stores mode + auxiliary fields together to preserve the selected preset.
public struct TimeRangeSpec: Hashable, Codable {
    public enum Mode: String, Codable {
        case any
        case last5m
        case last1h
        case today
        case customFixed     // from/to DatePicker
        case customLast      // "Last N unit" form
    }
    public var mode: Mode
    public var fromDate: Date?
    public var toDate: Date?
    public var lastN: Int?
    public var lastUnit: String?  // "min", "hour", "day"

    public init(mode: Mode = .any,
                fromDate: Date? = nil,
                toDate: Date? = nil,
                lastN: Int? = nil,
                lastUnit: String? = nil) {
        self.mode = mode
        self.fromDate = fromDate
        self.toDate = toDate
        self.lastN = lastN
        self.lastUnit = lastUnit
    }

    /// Computes the (from, to) range relative to the current time.
    public func toRange(now: Date = Date()) -> (Date?, Date?) {
        switch mode {
        case .any: return (nil, nil)
        case .last5m: return (now.addingTimeInterval(-300), nil)
        case .last1h: return (now.addingTimeInterval(-3600), nil)
        case .today: return (Calendar.current.startOfDay(for: now), nil)
        case .customFixed: return (fromDate, toDate)
        case .customLast:
            guard let n = lastN, n > 0 else { return (nil, nil) }
            let secs: TimeInterval
            switch lastUnit {
            case "hour": secs = TimeInterval(n) * 3600
            case "day":  secs = TimeInterval(n) * 86400
            default:     secs = TimeInterval(n) * 60   // "min" default
            }
            return (now.addingTimeInterval(-secs), nil)
        }
    }

    public var isEmpty: Bool {
        switch mode {
        case .any: return true
        case .customFixed: return fromDate == nil && toDate == nil
        case .customLast: return (lastN ?? 0) <= 0
        default: return false
        }
    }
}

public enum ColumnFilter: Hashable, Codable {
    case number(NumberSpec)
    case multiSelect(Set<String>)
    case text(String, regex: Bool)
    case timeRange(Date?, Date?)
    case compound(selected: Set<String>, text: String)
    case timeSpec(TimeRangeSpec)

    public var isEmpty: Bool {
        switch self {
        case .number(let s): return s.isEmpty
        case .multiSelect(let s): return s.isEmpty
        case .text(let t, _): return t.isEmpty
        case .timeRange(let a, let b): return a == nil && b == nil
        case .compound(let sel, let t): return sel.isEmpty && t.isEmpty
        case .timeSpec(let s): return s.isEmpty
        }
    }
}

public struct FilterState: Hashable, Codable {
    public var globalSearch: String = ""
    public var byColumn: [PortColumn: ColumnFilter] = [:]
    public init() {}
}
