import Foundation
import Darwin

let runner = CommandRunner()
let lsofParser = LsofParser()
let psParser = PsParser()
let stdout = FileHandle.standardOutput

func writeResponse(_ resp: HelperResponse) {
    if let data = try? HelperCodec.encodeLine(resp) {
        stdout.write(data)
    }
}

func handle(_ req: HelperRequest) async {
    switch req.op {
    case .ping:
        writeResponse(HelperResponse(id: req.id, ok: true))

    case .scan:
        do {
            let r = try await runner.run("/usr/sbin/lsof",
                                          args: ["-nP", "-iTCP", "-iUDP", "-F", "pcuLnPT"],
                                          timeout: 3.0)
            let entries = lsofParser.parse(r.stdoutString)
            writeResponse(HelperResponse(id: req.id, ok: true, entries: entries))
        } catch {
            writeResponse(HelperResponse(id: req.id, ok: false, message: "\(error)"))
        }

    case .kill:
        guard let pid = req.pid, let sig = req.sig else {
            writeResponse(HelperResponse(id: req.id, ok: false, message: "missing pid/sig"))
            return
        }
        let r = Darwin.kill(pid, sig)
        if r == 0 {
            writeResponse(HelperResponse(id: req.id, ok: true))
        } else {
            writeResponse(HelperResponse(id: req.id, ok: false, errno: errno))
        }

    case .procInfo:
        guard let pid = req.pid else {
            writeResponse(HelperResponse(id: req.id, ok: false, message: "missing pid"))
            return
        }
        let comm = try? await runner.run("/bin/ps", args: ["-o", "comm=", "-p", "\(pid)"], timeout: 1)
        let lstart = try? await runner.run("/bin/ps", args: ["-o", "lstart=", "-p", "\(pid)"], timeout: 1)
        let cwdOut = try? await runner.run("/usr/sbin/lsof", args: ["-p", "\(pid)", "-d", "cwd", "-Fn"], timeout: 1)
        let execPath = comm?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let startTime = lstart.flatMap { psParser.parseLstart($0.stdoutString) }
        let cwd = cwdOut.flatMap { psParser.parseCwd($0.stdoutString) }
        writeResponse(HelperResponse(
            id: req.id, ok: true,
            executablePath: (execPath?.isEmpty == false) ? execPath : nil,
            cwd: cwd,
            startTime: startTime
        ))
    }
}

// Read and process lines from stdin.
// @main / top-level await is restricted in main.swift, so
// we use the Task + RunLoop pattern as the entry point.
guard let inFile = fdopen(FileHandle.standardInput.fileDescriptor, "r") else {
    exit(1)
}

func readLoop() async {
    var lineBuf: UnsafeMutablePointer<CChar>? = nil
    var capacity: Int = 0
    defer { if let lb = lineBuf { free(lb) } }
    while true {
        let n = getline(&lineBuf, &capacity, inFile)
        if n <= 0 { return }
        guard let buf = lineBuf else { continue }
        let line = String(cString: buf)
        guard let data = line.data(using: .utf8) else { continue }
        if let req = try? HelperCodec.decode(HelperRequest.self, from: data) {
            await handle(req)
        }
    }
}

let mainTask = Task {
    await readLoop()
    exit(0)
}
_ = mainTask

RunLoop.main.run()
