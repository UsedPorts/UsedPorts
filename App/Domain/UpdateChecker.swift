import Foundation
import AppKit

/// Lightweight update check: fetches the latest tag from the GitHub Releases API
/// and compares it against the current bundle version. Notifies via callback if a new version is available.
/// No automatic installation — the user downloads manually from the Release page or runs brew upgrade.
@MainActor
public final class UpdateChecker: ObservableObject {
    private static let owner = "REPLACE_ME_OWNER"   // 실제 배포 시 GitHub username/org로 변경
    private static let repo = "used-ports"
    private static let autoCheckKey = "settings.autoCheckUpdates"
    private static let lastCheckKey = "settings.lastUpdateCheck"

    @Published public var autoCheckEnabled: Bool {
        didSet {
            guard oldValue != autoCheckEnabled else { return }
            UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey)
        }
    }
    @Published public var lastCheckDate: Date?
    @Published public var latestVersion: String?
    @Published public var isNewAvailable: Bool = false
    @Published public var releaseURL: URL?
    @Published public var isChecking: Bool = false

    public init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckEnabled = true
        } else {
            self.autoCheckEnabled = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        }
        self.lastCheckDate = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Called explicitly by the user or automatically on boot. Network errors are silently ignored.
    public func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = decoded.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            latestVersion = tag
            releaseURL = URL(string: decoded.htmlURL)
            isNewAvailable = Self.isNewer(tag, than: currentVersion)
            lastCheckDate = Date()
            UserDefaults.standard.set(lastCheckDate, forKey: Self.lastCheckKey)
        } catch {
            // Offline or other error — silently ignore.
        }
    }

    public func openReleasePage() {
        if let url = releaseURL { NSWorkspace.shared.open(url) }
    }

    /// Simple semantic version comparison. Assumes "1.2.3" format.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let c = candidate.split(separator: ".").compactMap { Int($0) }
        let r = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(c.count, r.count) {
            let a = i < c.count ? c[i] : 0
            let b = i < r.count ? r[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
