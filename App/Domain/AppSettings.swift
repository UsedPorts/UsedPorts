import Foundation
import SwiftUI
import ServiceManagement

public enum BackgroundRefreshMode: String, CaseIterable, Codable {
    case same       // Poll at the same interval whether the window is visible or not.
    case slower     // Default: double the interval when the window is hidden.
    case paused     // Stop polling while the window is hidden; resume on show.
}

@MainActor
public final class AppSettings: ObservableObject {
    private static let showMenuBarKey = "settings.showMenuBar"
    private static let appLanguageKey = "settings.appLanguage"
    private static let pinnedPortsKey = "settings.pinnedPorts"
    private static let menuBarCompactKey = "settings.menuBarCompact"
    private static let hideDuplicateRowsKey = "settings.hideDuplicateRows"
    private static let groupByPidKey = "settings.groupByPid"
    private static let showProcessIconsKey = "settings.showProcessIcons"
    private static let showGenericProcessIconKey = "settings.showGenericProcessIcon"
    private static let refreshIntervalKey = "settings.refreshIntervalSeconds"
    private static let backgroundRefreshModeKey = "settings.backgroundRefreshMode"

    /// Whether the NSStatusItem is shown in the menu bar. Changes are persisted to UserDefaults,
    /// and AppDelegate subscribes to this publisher to update statusItem.isVisible.
    @Published public var showMenuBar: Bool {
        didSet {
            guard oldValue != showMenuBar else { return }
            UserDefaults.standard.set(showMenuBar, forKey: Self.showMenuBarKey)
        }
    }

    /// Launch at login (synchronized with system state)
    @Published public var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// App language setting: "system" / "en" / "ko". Changes take effect on the next launch.
    @Published public var appLanguage: String {
        didSet {
            guard oldValue != appLanguage else { return }
            UserDefaults.standard.set(appLanguage, forKey: Self.appLanguageKey)
            applyAppLanguage(appLanguage)
        }
    }

    /// When true, the menu bar list hides the process name to show a denser port-only view.
    @Published public var menuBarCompact: Bool {
        didSet {
            guard oldValue != menuBarCompact else { return }
            UserDefaults.standard.set(menuBarCompact, forKey: Self.menuBarCompactKey)
        }
    }

    /// When true, rows whose visible columns are identical (pid, port, proto, IP family,
    /// address, state, user, process) are collapsed to the first occurrence. Differs only
    /// by file descriptor — lsof reports each fd separately, and dup/multi-listener sockets
    /// otherwise appear as visual duplicates in the table.
    @Published public var hideDuplicateRows: Bool {
        didSet {
            guard oldValue != hideDuplicateRows else { return }
            UserDefaults.standard.set(hideDuplicateRows, forKey: Self.hideDuplicateRowsKey)
        }
    }

    /// When true, the main table groups rows by PID. Processes that own ≥2 ports collapse
    /// into a parent row with a disclosure indicator; the parent shows port ranges and
    /// comma-joined proto/IP/address/state labels. Processes with a single port render as
    /// a normal leaf row (no indicator).
    @Published public var groupByPid: Bool {
        didSet {
            guard oldValue != groupByPid else { return }
            UserDefaults.standard.set(groupByPid, forKey: Self.groupByPidKey)
        }
    }

    /// When true, rows show the owning process's app icon next to its name (menu bar list and
    /// main table). GUI apps resolve to their icon; pure CLI/daemon processes have none and
    /// render a blank slot. On by default. See ProcessIconProvider.
    @Published public var showProcessIcons: Bool {
        didSet {
            guard oldValue != showProcessIcons else { return }
            UserDefaults.standard.set(showProcessIcons, forKey: Self.showProcessIconsKey)
        }
    }

    /// When true (and showProcessIcons is on), processes without their own app icon
    /// (CLI tools, daemons) render a generic executable icon instead of a blank slot.
    @Published public var showGenericProcessIcon: Bool {
        didSet {
            guard oldValue != showGenericProcessIcon else { return }
            UserDefaults.standard.set(showGenericProcessIcon, forKey: Self.showGenericProcessIconKey)
        }
    }

    /// Base poll interval for the lsof scanner, in seconds.
    @Published public var refreshIntervalSeconds: Double {
        didSet {
            guard oldValue != refreshIntervalSeconds else { return }
            UserDefaults.standard.set(refreshIntervalSeconds, forKey: Self.refreshIntervalKey)
        }
    }

    /// How the scanner behaves while the main window is hidden — keep the same cadence,
    /// halve it (default), or pause entirely until the window is shown again.
    @Published public var backgroundRefreshMode: BackgroundRefreshMode {
        didSet {
            guard oldValue != backgroundRefreshMode else { return }
            UserDefaults.standard.set(backgroundRefreshMode.rawValue, forKey: Self.backgroundRefreshModeKey)
        }
    }

    /// Port numbers to display as status text next to the menu bar icon. Sorting is applied at display time.
    @Published public var pinnedPorts: Set<UInt16> {
        didSet {
            guard oldValue != pinnedPorts else { return }
            let arr = Array(pinnedPorts).sorted().map { Int($0) }
            UserDefaults.standard.set(arr, forKey: Self.pinnedPortsKey)
        }
    }

    public func togglePin(port: UInt16) {
        if pinnedPorts.contains(port) {
            pinnedPorts.remove(port)
        } else {
            pinnedPorts.insert(port)
        }
    }

    public init() {
        if UserDefaults.standard.object(forKey: Self.showMenuBarKey) == nil {
            self.showMenuBar = true
        } else {
            self.showMenuBar = UserDefaults.standard.bool(forKey: Self.showMenuBarKey)
        }
        self.appLanguage = (UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? "system")
        if UserDefaults.standard.object(forKey: Self.menuBarCompactKey) == nil {
            self.menuBarCompact = true
        } else {
            self.menuBarCompact = UserDefaults.standard.bool(forKey: Self.menuBarCompactKey)
        }
        if UserDefaults.standard.object(forKey: Self.hideDuplicateRowsKey) == nil {
            self.hideDuplicateRows = true
        } else {
            self.hideDuplicateRows = UserDefaults.standard.bool(forKey: Self.hideDuplicateRowsKey)
        }
        if UserDefaults.standard.object(forKey: Self.groupByPidKey) == nil {
            self.groupByPid = true
        } else {
            self.groupByPid = UserDefaults.standard.bool(forKey: Self.groupByPidKey)
        }
        if UserDefaults.standard.object(forKey: Self.showProcessIconsKey) == nil {
            self.showProcessIcons = true
        } else {
            self.showProcessIcons = UserDefaults.standard.bool(forKey: Self.showProcessIconsKey)
        }
        if UserDefaults.standard.object(forKey: Self.showGenericProcessIconKey) == nil {
            self.showGenericProcessIcon = true
        } else {
            self.showGenericProcessIcon = UserDefaults.standard.bool(forKey: Self.showGenericProcessIconKey)
        }
        if UserDefaults.standard.object(forKey: Self.refreshIntervalKey) == nil {
            self.refreshIntervalSeconds = 3.0
        } else {
            let saved = UserDefaults.standard.double(forKey: Self.refreshIntervalKey)
            self.refreshIntervalSeconds = saved > 0 ? saved : 3.0
        }
        if let raw = UserDefaults.standard.string(forKey: Self.backgroundRefreshModeKey),
           let mode = BackgroundRefreshMode(rawValue: raw) {
            self.backgroundRefreshMode = mode
        } else {
            self.backgroundRefreshMode = .slower
        }
        if let arr = UserDefaults.standard.array(forKey: Self.pinnedPortsKey) as? [Int] {
            self.pinnedPorts = Set(arr.compactMap { UInt16(exactly: $0) })
        } else {
            self.pinnedPorts = []
        }
        // launchAtLogin starts as false; system state is synchronized asynchronously in syncFromSystem().
        // SMAppService.status may block or hang in some environments (e.g. test hosts).
        self.launchAtLogin = false
        // If a saved language preference exists, also apply it to AppleLanguages (effective on next launch).
        applyAppLanguage(appLanguage)
    }

    private func applyAppLanguage(_ lang: String) {
        if lang == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        }
    }

    /// Reads the SMAppService status from the system and synchronizes it with launchAtLogin.
    /// Call once at an appropriate point after launch (e.g. Settings window onAppear).
    public func syncFromSystem() {
        let actual = (SMAppService.mainApp.status == .enabled)
        if launchAtLogin != actual {
            launchAtLogin = actual
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // On failure, roll back to the actual state
            let actual = (SMAppService.mainApp.status == .enabled)
            if actual != self.launchAtLogin {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.launchAtLogin != actual {
                        self.launchAtLogin = actual
                    }
                }
            }
        }
    }
}
