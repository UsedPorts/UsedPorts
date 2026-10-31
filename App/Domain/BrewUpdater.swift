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
    /// Why the last install attempt failed; nil when it succeeded or none ran yet.
    @Published public var installError: String?

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
            brew, args: ["info", "--json=v2", "--formula", formula], timeout: 30
        ), res.exitCode == 0, let latest = BrewInfo.stableVersion(res.stdout)
        else { lastCheckFailed = true; lastCheckDate = Date(); return }
        // Compare against the running build, not brew's installed keg: after an upgrade
        // the keg can be current while ~/Applications still holds the old copy.
        if latest.compare(currentVersion, options: .numeric) == .orderedDescending {
            updateAvailable = true; latestVersion = latest
        } else {
            // Report current as latest so the UI still shows a latest-version line
            // (also covers a dev build newer than the tap).
            updateAvailable = false; latestVersion = currentVersion
        }
        lastCheckFailed = false
        lastCheckDate = Date()
    }

    public func installUpdate() { Task { await installUpdateAsync() } }

    func installUpdateAsync() async {
        guard let brew = brewPath, !isInstalling else { return }
        isInstalling = true
        installError = nil
        defer { isInstalling = false }
        let res: CommandResult
        do {
            res = try await runner.run(brew, args: ["upgrade", formula], timeout: 600)
        } catch {
            installError = "brew upgrade: \(error.localizedDescription)"
            return
        }
        guard res.exitCode == 0 else {
            installError = "brew upgrade exited with \(res.exitCode)"
            return
        }
        (relaunchHandler ?? { [weak self] in self?.relaunch() })()
    }

    public func openReleasesPage() {
        if let url = URL(string: "https://github.com/UsedPorts/UsedPorts/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The formula's `usedports` launcher, next to brew: it copies the Cellar app over
    /// ~/Applications/UsedPorts.app and opens it. Reopening our own bundle would just
    /// relaunch the old copy, since `brew upgrade` never touches ~/Applications.
    var launcherPath: String? {
        brewPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent(formula).path }
    }

    /// Quits only once the launcher is running; otherwise stays up and reports why,
    /// so a failed relaunch never leaves the user with no app.
    func relaunch() {
        guard let launcher = launcherPath, FileManager.default.isExecutableFile(atPath: launcher) else {
            installError = "launcher not found: \(launcherPath ?? "(no brew)")"
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to actually exit before the launcher runs: if `open` sees
        // the old instance still alive it just re-activates it. Gives up after ~10s
        // (e.g. termination was cancelled) instead of waiting forever.
        task.arguments = [
            "-c",
            #"i=0; while kill -0 "$2" 2>/dev/null; do i=$((i+1)); [ "$i" -ge 50 ] && exit 1; sleep 0.2; done; exec "$1""#,
            "--", launcher, String(getpid()),
        ]
        do {
            try task.run()
        } catch {
            installError = "launcher: \(error.localizedDescription)"
            return
        }
        NSApp.terminate(nil)
    }

    private func scheduleAutoCheck() {
        autoTimer?.invalidate()
        checkNow()
        // 3 hours. The check itself is cheap; the cost is `brew update`'s full
        // formula-index git sync, which is fine at this cadence.
        autoTimer = Timer.scheduledTimer(withTimeInterval: 10_800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }
}
