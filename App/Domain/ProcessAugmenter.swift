import Foundation

/// Per-process augmentation data (executable path, start time, cwd) resolved from `ps`/`lsof`.
public struct ProcessAugmentation: Sendable, Equatable {
    public var executablePath: String?
    public var startTime: Date?
    public var cwd: String?
    public init(executablePath: String? = nil, startTime: Date? = nil, cwd: String? = nil) {
        self.executablePath = executablePath
        self.startTime = startTime
        self.cwd = cwd
    }
}

public protocol ProcessAugmenting {
    /// Resolve augmentation data for many PIDs at once, keyed by PID. Batched so a
    /// list refresh spawns a constant number of subprocesses instead of one set per PID.
    func augment(pids: [Int32]) async -> [Int32: ProcessAugmentation]
}

public struct ProcessAugmenter: ProcessAugmenting {
    let runner: CommandRunning
    let ps: PsParser

    public init(runner: CommandRunning = CommandRunner(), ps: PsParser = PsParser()) {
        self.runner = runner; self.ps = ps
    }

    /// Bulk list augmentation: ONE `ps` call for the whole PID list. Only the start time
    /// is fetched — it's the sole augmented value any list column (Started) shows.
    /// Executable path and cwd are detail-pane-only, and batching `lsof -d cwd` over many
    /// PIDs is pathologically slow (~10s for ~45 PIDs), so they're deliberately excluded.
    public func augment(pids: [Int32]) async -> [Int32: ProcessAugmentation] {
        let valid = pids.filter { $0 > 0 }
        guard !valid.isEmpty else { return [:] }
        let list = valid.map(String.init).joined(separator: ",")
        let startMap = await fetchStartTimes(pidList: list)

        var out: [Int32: ProcessAugmentation] = [:]
        out.reserveCapacity(valid.count)
        for pid in valid {
            out[pid] = ProcessAugmentation(startTime: startMap[pid])
        }
        return out
    }

    /// Full single-entry augmentation for the detail pane (one selected row): exec path,
    /// start time, and cwd. Cheap because it's a single PID — the slow `lsof` cwd lookup
    /// runs for just one process, not the whole list.
    public func augment(_ entry: PortEntry) async -> PortEntry {
        guard entry.pid > 0 else { return entry }
        let list = String(entry.pid)
        async let execs = fetchExecutables(pidList: list)
        async let starts = fetchStartTimes(pidList: list)
        async let cwds = fetchCwds(pidList: list)
        let (execMap, startMap, cwdMap) = await (execs, starts, cwds)
        var e = entry
        e.executablePath = execMap[entry.pid]
        e.startTime = startMap[entry.pid]
        e.cwd = cwdMap[entry.pid]
        return e
    }

    private func fetchExecutables(pidList: String) async -> [Int32: String] {
        guard let r = try? await runner.run("/bin/ps", args: ["-o", "pid=,comm=", "-p", pidList], timeout: 2.0)
        else { return [:] }
        return ps.parsePidComm(r.stdoutString)
    }

    private func fetchStartTimes(pidList: String) async -> [Int32: Date] {
        guard let r = try? await runner.run("/bin/ps", args: ["-o", "pid=,lstart=", "-p", pidList], timeout: 2.0)
        else { return [:] }
        return ps.parsePidLstart(r.stdoutString)
    }

    private func fetchCwds(pidList: String) async -> [Int32: String] {
        guard let r = try? await runner.run("/usr/sbin/lsof", args: ["-p", pidList, "-d", "cwd", "-Fn"], timeout: 3.0)
        else { return [:] }
        return ps.parsePidCwds(r.stdoutString)
    }
}
