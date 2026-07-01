import Foundation

public struct PsParser {
    public init() {}

    private static let lstartFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    public func parseLstart(_ s: String) -> Date? {
        let normalized = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return Self.lstartFormatter.date(from: normalized)
    }

    /// Extracts the cwd path from `lsof -p PID -d cwd -Fn` output.
    public func parseCwd(_ s: String) -> String? {
        for raw in s.split(separator: "\n") {
            if raw.hasPrefix("n") { return String(raw.dropFirst()) }
        }
        return nil
    }

    // MARK: - Batched (many PIDs at once)

    /// Parses `ps -o pid=,comm= -p ...`: each line is "PID  <exec path>". The path may
    /// contain spaces, so everything after the first field is the executable.
    public func parsePidComm(_ s: String) -> [Int32: String] {
        var out: [Int32: String] = [:]
        for line in s.split(separator: "\n") {
            guard let (pid, rest) = splitPidPrefix(line) else { continue }
            let comm = rest.trimmingCharacters(in: .whitespaces)
            if !comm.isEmpty { out[pid] = comm }
        }
        return out
    }

    /// Parses `ps -o pid=,lstart= -p ...`: each line is "PID  Www Mmm D HH:MM:SS YYYY".
    public func parsePidLstart(_ s: String) -> [Int32: Date] {
        var out: [Int32: Date] = [:]
        for line in s.split(separator: "\n") {
            guard let (pid, rest) = splitPidPrefix(line) else { continue }
            if let date = parseLstart(rest) { out[pid] = date }
        }
        return out
    }

    /// Parses `lsof -p ... -d cwd -Fn`: repeated `p<pid>` / `fcwd` / `n<path>` blocks.
    public func parsePidCwds(_ s: String) -> [Int32: String] {
        var out: [Int32: String] = [:]
        var current: Int32?
        for raw in s.split(separator: "\n") {
            if raw.hasPrefix("p") {
                current = Int32(raw.dropFirst())
            } else if raw.hasPrefix("n"), let pid = current, out[pid] == nil {
                out[pid] = String(raw.dropFirst())
            }
        }
        return out
    }

    /// Splits a leading, possibly space-padded PID field from the rest of the line.
    private func splitPidPrefix(_ line: Substring) -> (Int32, String)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard let sp = trimmed.firstIndex(of: " "),
              let pid = Int32(trimmed[..<sp]) else { return nil }
        return (pid, String(trimmed[trimmed.index(after: sp)...]))
    }
}
