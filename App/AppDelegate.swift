import AppKit
import SwiftUI
import Combine

/// Holds the app-level state (ViewModel, PrivilegeManager, AppSettings, ToastCenter)
/// so both the SwiftUI scenes and the AppKit menu bar code can share a single
/// source of truth.
@MainActor
final class AppHostStore: ObservableObject {
    let scanner: PortScanner
    let viewModel: PortListViewModel
    let privilege: PrivilegeManager
    let settings: AppSettings
    let toasts: ToastCenter
    let updater: BrewUpdater
    let logStore: LogStore
    let portNotifier: PinnedPortNotifier

    private var refreshCancellables: Set<AnyCancellable> = []

    init() {
        let scanner = PortScanner()
        let toasts = ToastCenter()
        let logStore = LogStore()
        let viewModel = PortListViewModel(scanner: scanner, toasts: toasts)
        let privilege = PrivilegeManager(scanner: scanner, toasts: toasts, logStore: logStore)
        let settings = AppSettings()
        let updater = BrewUpdater()
        self.scanner = scanner
        self.viewModel = viewModel
        self.privilege = privilege
        self.settings = settings
        self.toasts = toasts
        self.updater = updater
        self.logStore = logStore
        let portNotifier = PinnedPortNotifier(settings: settings)
        self.portNotifier = portNotifier
        viewModel.portNotifier = portNotifier

        // Seed the scanner config from persisted settings, then propagate runtime changes.
        viewModel.setRefreshInterval(settings.refreshIntervalSeconds)
        viewModel.setBackgroundRefreshMode(settings.backgroundRefreshMode)
        settings.$refreshIntervalSeconds
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak viewModel] interval in viewModel?.setRefreshInterval(interval) }
            .store(in: &refreshCancellables)
        settings.$backgroundRefreshMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak viewModel] mode in viewModel?.setBackgroundRefreshMode(mode) }
            .store(in: &refreshCancellables)

        logStore.info("App started")
    }
}

/// SwiftUI view that the AppDelegate hosts inside the NSPopover. Wraps the
/// existing `MenuBarContent` so that the popover renders the same UI that the
/// previous `MenuBarExtra` scene used.
struct AppDelegateMenuBarView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var toasts: ToastCenter

    var body: some View {
        MenuBarContent(viewModel: viewModel,
                       privilege: privilege,
                       settings: settings,
                       toasts: toasts)
    }
}

/// Manages the lifecycle of the menu-bar `NSStatusItem` and its `NSPopover`.
///
/// Owning the menu bar from AppKit (rather than SwiftUI `MenuBarExtra`) lets us
/// toggle the icon at runtime via `AppSettings.showMenuBar`, and avoids the
/// `MenuBarExtra(isInserted:)` launch hang seen in Xcode 26 test hosts.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let host: AppHostStore

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var visibilityCancellable: AnyCancellable?
    private var titleCancellables: Set<AnyCancellable> = []

    override init() {
        self.host = AppHostStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        observeVisibility()
        observePinnedPorts()
        observeAppActivation()
        observeWindowsForDock()
    }

    /// Show the Dock icon only while a normal app window (main or Settings) is open;
    /// otherwise the app lives purely in the menu bar with no Dock presence.
    private func observeWindowsForDock() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(managedWindowOpened(_:)),
                       name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(managedWindowWillClose(_:)),
                       name: NSWindow.willCloseNotification, object: nil)
    }

    /// A real app window, not the menu-bar popover (canBecomeMain is false for it) or panels.
    private func isManagedWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain && !(window is NSPanel)
    }

    @objc private func managedWindowOpened(_ note: Notification) {
        guard let w = note.object as? NSWindow, isManagedWindow(w) else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @objc private func managedWindowWillClose(_ note: Notification) {
        guard let w = note.object as? NSWindow, isManagedWindow(w) else { return }
        // The window is still open during willClose; recompute on the next tick.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasWindow = NSApp.windows.contains { $0.isVisible && self.isManagedWindow($0) }
            if !hasWindow, NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Drop to background refresh cadence when the app isn't the active app (e.g. the
    /// user ⌘Tab'd away while leaving the window open), and restore on reactivation.
    private func observeAppActivation() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appDidBecomeActive),
                       name: NSApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDidResignActive),
                       name: NSApplication.didResignActiveNotification, object: nil)
        host.viewModel.setAppActive(NSApp.isActive)
    }

    @objc private func appDidBecomeActive() { host.viewModel.setAppActive(true) }
    @objc private func appDidResignActive() { host.viewModel.setAppActive(false) }

    /// Updates the status text next to the menu bar icon (pinned port state) whenever pinnedPorts,
    /// rawEntries, or the "ports-only" compact toggle changes.
    private func observePinnedPorts() {
        host.settings.$pinnedPorts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemTitle() }
            .store(in: &titleCancellables)
        host.viewModel.$rawEntries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemTitle() }
            .store(in: &titleCancellables)
        host.settings.$menuBarCompact
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItemTitle() }
            .store(in: &titleCancellables)
        updateStatusItemTitle()
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        let pinned = host.settings.pinnedPorts.sorted()
        if pinned.isEmpty {
            button.attributedTitle = NSAttributedString()
            return
        }
        let byPort = Dictionary(grouping: host.viewModel.rawEntries, by: { $0.port })
        let showName = !host.settings.menuBarCompact
        let portFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let dotFont = NSFont.systemFont(ofSize: 7, weight: .bold)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "  "))
        for (i, port) in pinned.enumerated() {
            let entry = byPort[port]?.first
            let isActive = (entry != nil)
            let dotColor: NSColor = isActive ? .systemGreen : .tertiaryLabelColor
            let textColor: NSColor = isActive ? .labelColor : .tertiaryLabelColor
            let dotAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: dotColor,
                .font: dotFont,
                .baselineOffset: 2,
            ]
            let portAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: portFont,
            ]
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .font: nameFont,
            ]
            result.append(NSAttributedString(string: isActive ? "● " : "○ ", attributes: dotAttrs))
            result.append(NSAttributedString(string: "\(port)", attributes: portAttrs))
            if showName, let name = entry?.processName, !name.isEmpty {
                result.append(NSAttributedString(string: " \(name)", attributes: nameAttrs))
            }
            if i < pinned.count - 1 {
                result.append(NSAttributedString(string: "  ", attributes: portAttrs))
            }
        }
        button.attributedTitle = result
    }

    // MARK: - Setup

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let menuBarImage = NSImage(named: "MenuBarIcon")
            menuBarImage?.isTemplate = true
            menuBarImage?.accessibilityDescription = "UsedPorts"
            button.image = menuBarImage
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 420, height: 520)
        let rootView = AppDelegateMenuBarView(
            viewModel: host.viewModel,
            privilege: host.privilege,
            settings: host.settings,
            toasts: host.toasts
        )
        pop.contentViewController = NSHostingController(rootView: rootView)
        popover = pop
    }

    private func observeVisibility() {
        visibilityCancellable = host.settings.$showMenuBar
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.statusItem?.isVisible = visible
            }
        statusItem?.isVisible = host.settings.showMenuBar
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Show the cached list instantly, then kick a fresh scan that updates
            // the rows in place when it completes — no blocking on open.
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Task { try? await host.viewModel.refreshOnce() }
        }
    }
}
