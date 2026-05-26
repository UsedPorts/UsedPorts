import Foundation
import AppKit

@MainActor
public final class BrewUpdater: NSObject, ObservableObject {
    @Published public var autoCheckEnabled: Bool = false
    @Published public var lastCheckDate: Date?
    @Published public var isChecking: Bool = false

    public var canCheckNow: Bool { false }

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public func checkNow() {}
}
