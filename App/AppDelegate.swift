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
    let updater: UpdateChecker
    let logStore: LogStore

    init() {
        let scanner = PortScanner()
        let toasts = ToastCenter()
        let logStore = LogStore()
        let viewModel = PortListViewModel(scanner: scanner, toasts: toasts)
        let privilege = PrivilegeManager(scanner: scanner, toasts: toasts, logStore: logStore)
        let settings = AppSettings()
        let updater = UpdateChecker()
        self.scanner = scanner
        self.viewModel = viewModel
        self.privilege = privilege
        self.settings = settings
        self.toasts = toasts
        self.updater = updater
        self.logStore = logStore
        logStore.info("App started")
    }
}

/// SwiftUI view that the AppDelegate hosts inside the NSPopover. Wraps the
/// existing `MenuBarContent` so that the popover renders the same UI that the
/// previous `MenuBarExtra` scene used.
struct AppDelegateMenuBarView: View {
    @ObservedObject var viewModel: PortListViewModel
    @ObservedObject var privilege: PrivilegeManager

    var body: some View {
        MenuBarContent(viewModel: viewModel, privilege: privilege)
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

    override init() {
        self.host = AppHostStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        observeVisibility()
        observeUpdateChecker()
        Task { [host] in
            // Auto-check on launch (noop if disabled). Results are surfaced via host.toasts.
            if host.updater.autoCheckEnabled {
                await host.updater.checkNow()
            }
        }
    }

    private func observeUpdateChecker() {
        // Show a toast banner when a new version is found.
        Task { [host] in
            for await _ in host.updater.$isNewAvailable.values where host.updater.isNewAvailable {
                let v = host.updater.latestVersion ?? "?"
                host.toasts.showBanner(String(localized: "New version \(v) is available"))
            }
        }
    }

    // MARK: - Setup

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "network",
                                   accessibilityDescription: "UsedPorts")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 360, height: 480)
        let rootView = AppDelegateMenuBarView(
            viewModel: host.viewModel,
            privilege: host.privilege
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
