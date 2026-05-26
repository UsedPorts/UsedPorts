import Foundation
import AppKit

@MainActor
public final class BrewUpdater: NSObject, ObservableObject {
    private let runner: CommandRunning
    private let brewPath: String?
    private let formula: String
    private let relaunchHandler: (() -> Void)?

    @Published public var autoCheckEnabled: Bool {
        didSet {
            guard oldValue != autoCheckEnabled else { return }
            UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoKey)
            if autoCheckEnabled { scheduleAutoCheck() } else { autoTimer?.invalidate() }
        }
    }
    @Published public var lastCheckDate: Date?
    @Published public var isChecking: Bool = false
    @Published public var isInstalling: Bool = false
    @Published public var updateAvailable: Bool = false
    @Published public var latestVersion: String?
    @Published public var lastCheckFailed: Bool = false

    private var autoTimer: Timer?
    private static let autoKey = "BrewUpdater.autoCheckEnabled"

    public init(runner: CommandRunning = CommandRunner(),
                brewPath: String? = BrewLocator.path(),
                formula: String = "usedports",
                relaunchHandler: (() -> Void)? = nil) {
        self.runner = runner
        self.brewPath = brewPath
        self.formula = formula
        self.relaunchHandler = relaunchHandler
        self.autoCheckEnabled = UserDefaults.standard.bool(forKey: Self.autoKey)
        super.init()
        if autoCheckEnabled { scheduleAutoCheck() }
    }

    public var isManagedByBrew: Bool { brewPath != nil }
    public var canCheckNow: Bool { brewPath != nil && !isChecking }

    public var currentVersion: String { AppVersion.short }

    public func checkNow() { Task { await checkNowAsync() } }

    func checkNowAsync() async {
        guard let brew = brewPath, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        _ = try? await runner.run(brew, args: ["update"], timeout: 60)
        guard let res = try? await runner.run(
            brew, args: ["outdated", "--json", "--formula", formula], timeout: 30
        ) else { lastCheckFailed = true; lastCheckDate = Date(); return }
        switch BrewOutdated.parse(res.stdout, formula: formula) {
        case .available(let latest):
            updateAvailable = true; latestVersion = latest
        case .upToDate:
            updateAvailable = false; latestVersion = nil
        }
        lastCheckFailed = false
        lastCheckDate = Date()
    }

    public func installUpdate() { Task { await installUpdateAsync() } }

    func installUpdateAsync() async {
        guard let brew = brewPath, !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }
        guard let res = try? await runner.run(
            brew, args: ["upgrade", formula], timeout: 600
        ), res.exitCode == 0 else { return }
        (relaunchHandler ?? { [weak self] in self?.relaunch() })()
    }

    public func openReleasesPage() {
        if let url = URL(string: "https://github.com/UsedPorts/UsedPorts/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    private func relaunch() {
        let appPath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; exec /usr/bin/open -n \"$1\"", "--", appPath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func scheduleAutoCheck() {
        autoTimer?.invalidate()
        checkNow()
        autoTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }
}
