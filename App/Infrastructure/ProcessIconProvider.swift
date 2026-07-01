import AppKit
import UniformTypeIdentifiers

/// Resolves a process's app icon from its pid. Abstracted so the caching layer
/// can be unit-tested without depending on live system processes.
public protocol RunningAppIconResolving {
    func icon(forPID pid: pid_t) -> NSImage?
}

/// Production resolver: GUI app bundles return their icon, pure CLI/daemon
/// processes (node, python, the postgres binary, …) return nil. This is the
/// cheap, system-cached path — no proc_pidpath / LaunchServices disk lookups.
public struct SystemIconResolver: RunningAppIconResolving {
    public init() {}
    public func icon(forPID pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}

/// Caches pid → icon so a given pid is resolved at most once while it stays
/// alive. App icons do not change at runtime, so live pids are never
/// re-resolved; the cache is kept honest purely by pruning pids that have left
/// the latest poll snapshot (which also covers pid reuse: a recycled pid
/// becomes a cache miss and is resolved afresh).
@MainActor
public final class ProcessIconProvider {
    private let resolver: RunningAppIconResolving
    // nil is cached too, so CLI processes are not re-resolved every lookup.
    private var cache: [pid_t: NSImage?] = [:]

    /// Shown for processes without their own app icon (CLI tools, daemons) so the
    /// icon column is never blank — macOS's generic Unix-executable icon.
    static let genericIcon: NSImage = NSWorkspace.shared.icon(for: .unixExecutable)

    public init(resolver: RunningAppIconResolving = SystemIconResolver()) {
        self.resolver = resolver
    }

    /// Cache-first lookup. Resolves (and caches, including a nil app-icon result) on
    /// miss, then falls back to the generic icon so callers always get something to show.
    public func icon(forPID pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached ?? Self.genericIcon }
        let resolved = resolver.icon(forPID: pid)
        cache[pid] = resolved
        return resolved ?? Self.genericIcon
    }

    /// Drop cached entries whose pid is no longer present in the latest snapshot.
    public func prune(livePIDs: Set<pid_t>) {
        cache = cache.filter { livePIDs.contains($0.key) }
    }

    /// Test/inspection hook: number of cached pids.
    var cachedCount: Int { cache.count }
}
