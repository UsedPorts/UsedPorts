import Foundation

/// App version read from the bundle's Info.plist, for display in the UI.
public enum AppVersion {
    /// Marketing version, e.g. "0.1.0".
    public static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Version prefixed with "v" for display, e.g. "v0.1.0".
    public static var display: String { "v\(short)" }
}
