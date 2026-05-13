import Foundation
import AppKit

/// In-memory rolling log of recent events. Drives the "Help / Report Issue"
/// flow in Settings: users can save the log to a file or open a pre-filled
/// GitHub Issue (and attach the log there themselves).
@MainActor
public final class LogStore: ObservableObject {
    public enum Level: String, Codable {
        case info, warning, error
    }

    public struct Entry: Identifiable, Codable {
        public let id: UUID
        public let timestamp: Date
        public let level: Level
        public let message: String

        public init(id: UUID = UUID(), timestamp: Date = Date(), level: Level, message: String) {
            self.id = id
            self.timestamp = timestamp
            self.level = level
            self.message = message
        }
    }

    @Published public private(set) var entries: [Entry] = []
    private let maxEntries = 1000

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    public init() {}

    public func log(_ level: Level, _ message: String) {
        entries.append(Entry(level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func info(_ message: String)    { log(.info, message) }
    public func warning(_ message: String) { log(.warning, message) }
    public func error(_ message: String)   { log(.error, message) }

    /// Render a full diagnostic report (header + entries) as plain text.
    public func renderReport() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let locale = Locale.current.identifier
        var s = ""
        s += "UsedPorts diagnostic report\n"
        s += "============================\n"
        s += "App version: \(appVersion) (\(build))\n"
        s += "macOS: \(os)\n"
        s += "Locale: \(locale)\n"
        s += "Generated: \(Self.dateFormatter.string(from: Date()))\n"
        s += "Entries: \(entries.count)\n\n"
        for e in entries {
            s += "[\(Self.dateFormatter.string(from: e.timestamp))] "
            s += "\(e.level.rawValue.uppercased()): "
            s += "\(e.message)\n"
        }
        return s
    }

    /// Save the report to a user-chosen location via NSSavePanel.
    /// Returns the URL on success, nil if the user cancelled or save failed.
    @discardableResult
    public func saveReport() async -> URL? {
        let report = renderReport()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let stamp = Self.dateFormatter.string(from: Date()).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "usedports-log-\(stamp).txt"
        panel.title = "Save Diagnostic Log"
        let response = await panel.beginAsync()
        guard response == .OK, let url = panel.url else { return nil }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Open a pre-filled GitHub Issue page. The log itself is too large to
    /// embed in a URL, so the body explains what to attach; we also drop the
    /// log into the clipboard so the user can paste it.
    public func openGitHubIssue() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(renderReport(), forType: .string)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
        ## What happened

        <!-- Describe what you were doing when the issue happened -->

        ## Diagnostic info
        - App version: \(appVersion)
        - macOS: \(os)

        ## Log
        <!-- The diagnostic log has been copied to your clipboard. Paste it below. -->

        ```
        (paste log here)
        ```
        """
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://github.com/UsedPorts/UsedPorts/issues/new?title=Issue&body=\(encoded)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension NSSavePanel {
    /// Async wrapper for the begin sheet/modal flow.
    @MainActor
    func beginAsync() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            self.begin { response in
                cont.resume(returning: response)
            }
        }
    }
}
