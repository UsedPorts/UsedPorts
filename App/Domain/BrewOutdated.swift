import Foundation

/// Latest version the tap offers, read from `brew info --json=v2`. Compared against the
/// running app rather than the brew-installed keg: `brew upgrade` only updates the Cellar,
/// so the copy in ~/Applications can lag behind what brew considers installed.
public enum BrewInfo {
    private struct Payload: Decodable {
        struct Formula: Decodable {
            struct Versions: Decodable { let stable: String? }
            let versions: Versions
        }
        let formulae: [Formula]
    }

    /// nil when the output isn't the expected JSON or carries no stable version.
    public static func stableVersion(_ data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload.formulae.first?.versions.stable
    }
}

public enum BrewLocator {
    static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    public static func path(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        candidates.first(where: exists)
    }
}
