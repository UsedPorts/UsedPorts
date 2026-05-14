import Foundation
import AppKit
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`. Sparkle
/// handles detection, download, signature verification, and the install
/// dialog. The view layer only needs the @Published mirrors below.
@MainActor
public final class UpdateChecker: NSObject, ObservableObject {
    private let controller: SPUStandardUpdaterController

    @Published public var autoCheckEnabled: Bool {
        didSet {
            guard oldValue != autoCheckEnabled else { return }
            controller.updater.automaticallyChecksForUpdates = autoCheckEnabled
        }
    }
    @Published public var lastCheckDate: Date?
    @Published public var isChecking: Bool = false

    public override init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.autoCheckEnabled = controller.updater.automaticallyChecksForUpdates
        self.lastCheckDate = controller.updater.lastUpdateCheckDate
        super.init()
    }

    public var canCheckNow: Bool {
        controller.updater.canCheckForUpdates
    }

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// User-driven check. Sparkle presents its own UI; `lastCheckDate` is
    /// refreshed shortly after Sparkle's sheet closes.
    public func checkNow() {
        guard !isChecking else { return }
        isChecking = true
        controller.checkForUpdates(nil)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                guard let self else { return }
                self.lastCheckDate = self.controller.updater.lastUpdateCheckDate
                self.isChecking = false
            }
        }
    }
}
