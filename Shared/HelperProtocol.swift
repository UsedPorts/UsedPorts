import Foundation

public enum HelperOp: String, Codable {
    case scan
    case kill
    case procInfo = "proc-info"
    case ping
}

public struct HelperRequest: Codable, Equatable {
    public var id: String
    public var op: HelperOp
    public var pid: Int32?
    public var sig: Int32?
    public init(id: String, op: HelperOp, pid: Int32? = nil, sig: Int32? = nil) {
        self.id = id; self.op = op; self.pid = pid; self.sig = sig
    }
}

public struct HelperResponse: Codable, Equatable {
    public var id: String
    public var ok: Bool
    public var entries: [PortEntry]?
    public var executablePath: String?
    public var cwd: String?
    public var startTime: Date?
    public var errno: Int32?
    public var message: String?

    public init(id: String, ok: Bool,
                entries: [PortEntry]? = nil,
                executablePath: String? = nil,
                cwd: String? = nil,
                startTime: Date? = nil,
                errno: Int32? = nil,
                message: String? = nil) {
        self.id = id; self.ok = ok
        self.entries = entries
        self.executablePath = executablePath
        self.cwd = cwd
        self.startTime = startTime
        self.errno = errno
        self.message = message
    }
}

public struct HelperCodec {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A) // \n
        return data
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        return try decoder.decode(type, from: data)
    }
}
