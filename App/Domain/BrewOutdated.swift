import Foundation

public enum BrewOutdated: Equatable {
    case upToDate
    case available(latest: String)

    private struct Payload: Decodable {
        struct Formula: Decodable { let name: String; let current_version: String }
        let formulae: [Formula]
    }

    public static func parse(_ data: Data, formula: String) -> BrewOutdated {
        // brew reports the tap-qualified name ("usedports/tap/usedports") for
        // tapped formulae, so match the trailing token, not just the bare name.
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let match = payload.formulae.first(where: {
                  $0.name == formula || $0.name.hasSuffix("/" + formula)
              }) else {
            return .upToDate
        }
        return .available(latest: match.current_version)
    }
}

public enum BrewLocator {
    static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    public static func path(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        candidates.first(where: exists)
    }
}
