import Foundation
import SwiftUI
import ServiceManagement

@MainActor
public final class AppSettings: ObservableObject {
    private static let showMenuBarKey = "settings.showMenuBar"
    private static let appLanguageKey = "settings.appLanguage"
    private static let pinnedPortsKey = "settings.pinnedPorts"
    private static let menuBarCompactKey = "settings.menuBarCompact"
    private static let menuBarGroupSamePidKey = "settings.menuBarGroupSamePid"

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

    /// When true, adjacent rows sharing a PID suppress the repeated process name,
    /// producing a "one cell, two lines" look for same-process port groups.
    @Published public var menuBarGroupSamePid: Bool {
        didSet {
            guard oldValue != menuBarGroupSamePid else { return }
            UserDefaults.standard.set(menuBarGroupSamePid, forKey: Self.menuBarGroupSamePidKey)
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
        self.menuBarCompact = UserDefaults.standard.bool(forKey: Self.menuBarCompactKey)
        if UserDefaults.standard.object(forKey: Self.menuBarGroupSamePidKey) == nil {
            self.menuBarGroupSamePid = true
        } else {
            self.menuBarGroupSamePid = UserDefaults.standard.bool(forKey: Self.menuBarGroupSamePidKey)
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
