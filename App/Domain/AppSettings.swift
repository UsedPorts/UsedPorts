import Foundation
import SwiftUI
import ServiceManagement

@MainActor
public final class AppSettings: ObservableObject {
    private static let showMenuBarKey = "settings.showMenuBar"
    private static let appLanguageKey = "settings.appLanguage"
    private static let pinnedPortsKey = "settings.pinnedPorts"

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

    public init() {
        if UserDefaults.standard.object(forKey: Self.showMenuBarKey) == nil {
            self.showMenuBar = true
        } else {
            self.showMenuBar = UserDefaults.standard.bool(forKey: Self.showMenuBarKey)
        }
        self.appLanguage = (UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? "system")
        if let arr = UserDefaults.standard.array(forKey: Self.pinnedPortsKey) as? [Int] {
            self.pinnedPorts = Set(arr.compactMap { UInt16(exactly: $0) })
        } else {
            self.pinnedPorts = []
        }
        // launchAtLogin starts as false; system state is synchronized asynchronously in syncFromSystem().
        // SMAppService.status may block or hang in some environments (e.g. test hosts).
        self.launchAtLogin = false
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
