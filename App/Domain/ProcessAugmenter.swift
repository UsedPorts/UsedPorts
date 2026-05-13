import Foundation

public protocol ProcessAugmenting {
    func augment(_ entry: PortEntry) async -> PortEntry
}

public struct ProcessAugmenter: ProcessAugmenting {
    let runner: CommandRunning
    let ps: PsParser

    public init(runner: CommandRunning = CommandRunner(), ps: PsParser = PsParser()) {
        self.runner = runner; self.ps = ps
    }

    public func augment(_ entry: PortEntry) async -> PortEntry {
        var e = entry
        async let execPath = fetchExecutable(pid: entry.pid)
        async let start = fetchStartTime(pid: entry.pid)
        async let cwd = fetchCwd(pid: entry.pid)
        e.executablePath = await execPath
        e.startTime = await start
        e.cwd = await cwd
        return e
    }

    private func fetchExecutable(pid: Int32) async -> String? {
        guard let r = try? await runner.run("/bin/ps", args: ["-o", "comm=", "-p", "\(pid)"], timeout: 1.0)
        else { return nil }
        let s = r.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func fetchStartTime(pid: Int32) async -> Date? {
        guard let r = try? await runner.run("/bin/ps", args: ["-o", "lstart=", "-p", "\(pid)"], timeout: 1.0)
        else { return nil }
        return ps.parseLstart(r.stdoutString)
    }

    private func fetchCwd(pid: Int32) async -> String? {
        guard let r = try? await runner.run("/usr/sbin/lsof", args: ["-p", "\(pid)", "-d", "cwd", "-Fn"], timeout: 1.0)
        else { return nil }
        return ps.parseCwd(r.stdoutString)
    }
}
