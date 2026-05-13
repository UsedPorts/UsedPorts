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
}
