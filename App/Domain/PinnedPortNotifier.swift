import Foundation
import AppKit
import UserNotifications

/// Watches poll batches for pinned ports appearing/disappearing and delivers user
/// notifications (Settings → Notifications). The diff itself is a pure static function
/// so it is unit-testable; this class owns the baseline state and UNUserNotificationCenter
/// delivery. Fed every batch from PortListViewModel.applyBatch.
@MainActor
public final class PinnedPortNotifier: NSObject, ObservableObject {
    public struct PortEvent: Equatable {
        public enum Kind: Equatable { case opened, closed }
        public let port: UInt16
        public let kind: Kind
    }

    /// Snapshot of the process behind a port, kept per batch so "closed" events can
    /// still describe the process that just went away.
    public struct PortProcessInfo: Equatable {
        public let name: String
        public let pid: Int32
        public let address: String
    }

    /// True when the user enabled the feature but macOS notification permission is denied.
    /// Settings shows a warning + "Open System Settings" button off this flag.
    @Published public private(set) var authorizationDenied = false

    private let settings: AppSettings
    // All open ports from the previous batch (nil until the first batch establishes the
    // baseline — the first observation never fires notifications). Tracking every open
    // port, not just pinned ones, means pinning an already-open port can't fabricate an
    // "opened" event on the next poll.
    private var lastOpenPorts: Set<UInt16>?
    private var lastInfo: [UInt16: PortProcessInfo] = [:]

    public init(settings: AppSettings) {
        self.settings = settings
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Pure diff: which pinned ports flipped between two open-port snapshots, filtered
    /// by the trigger setting. Ports are reported in ascending order for stable output.
    public nonisolated static func events(
        previous: Set<UInt16>,
        current: Set<UInt16>,
        pinned: Set<UInt16>,
        trigger: PinnedPortNotificationTrigger
    ) -> [PortEvent] {
        var out: [PortEvent] = []
        if trigger != .closed {
            out += current.subtracting(previous).intersection(pinned)
                .map { PortEvent(port: $0, kind: .opened) }
        }
        if trigger != .opened {
            out += previous.subtracting(current).intersection(pinned)
                .map { PortEvent(port: $0, kind: .closed) }
        }
        return out.sorted { $0.port < $1.port }
    }

    public func ingest(_ batch: [PortEntry]) {
        let open = Set(batch.map(\.port))
        var info: [UInt16: PortProcessInfo] = [:]
        for e in batch where info[e.port] == nil {
            info[e.port] = PortProcessInfo(name: e.processName, pid: e.pid, address: e.localAddress)
        }
        defer {
            lastOpenPorts = open
            lastInfo = info
        }
        guard let previous = lastOpenPorts, previous != open,
              settings.pinnedPortNotificationsEnabled else { return }
        for event in Self.events(previous: previous,
                                 current: open,
                                 pinned: settings.pinnedPorts,
                                 trigger: settings.pinnedPortNotificationTrigger) {
            deliver(event, info: event.kind == .opened ? info[event.port] : lastInfo[event.port])
        }
    }

    /// Notification copy, separated for unit testing. Port and PID are interpolated as
    /// pre-built Strings: interpolating Int into String(localized:) applies locale number
    /// formatting and renders "Port 8,787".
    public nonisolated static func message(
        for event: PortEvent, info: PortProcessInfo?
    ) -> (title: String, body: String?) {
        let port = String(event.port)
        let title = event.kind == .opened
            ? String(localized: "Port \(port) opened")
            : String(localized: "Port \(port) closed")
        let body = info.map { i -> String in
            let pid = String(i.pid)
            if i.name.isEmpty {
                return String(localized: "\(i.address) · PID \(pid)")
            }
            return String(localized: "\(i.name) · \(i.address) · PID \(pid)")
        }
        return (title, body)
    }

    private func deliver(_ event: PortEvent, info: PortProcessInfo?) {
        let (title, body) = Self.message(for: event, info: info)
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Re-reads the system authorization status (call on Settings appear and app activation,
    /// so returning from System Settings clears/raises the warning).
    public func refreshAuthorizationStatus() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            authorizationDenied = (status == .denied)
        }
    }

    /// First-time permission prompt, triggered by turning the Settings toggle on — never at launch.
    public func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let status = await center.notificationSettings().authorizationStatus
            authorizationDenied = (status == .denied)
        }
    }

    /// Deep-links to this app's row in System Settings → Notifications.
    public func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension PinnedPortNotifier: UNUserNotificationCenterDelegate {
    // Show banners even while UsedPorts is the active app (default is to suppress them).
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
