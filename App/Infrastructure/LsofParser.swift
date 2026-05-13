import Foundation

public struct LsofParser {
    public init() {}

    /// Parses `lsof -F pcuLnPTt` output.
    /// The added `t` field is the file TYPE (e.g. IPv4, IPv6), used to distinguish IP family.
    public func parse(_ text: String) -> [PortEntry] {
        var result: [PortEntry] = []

        var curPid: Int32? = nil
        var curCommand: String = ""
        var curUser: String = ""

        var curFd: String = ""
        var curProto: NetProto? = nil
        var curIPFamily: IPFamily? = nil
        var curName: String = ""
        var curState: String? = nil

        func flushFd() {
            guard let pid = curPid, let proto = curProto, !curName.isEmpty else { return }
            let localPart = curName.split(separator: "-", maxSplits: 1).first.map(String.init) ?? curName
            guard let (addr, port) = splitAddrPort(localPart) else { return }
            let famSuffix = curIPFamily?.rawValue ?? "-"
            let id = "\(pid)-\(curFd)-\(proto.rawValue)-\(famSuffix)-\(port)"
            result.append(PortEntry(
                id: id,
                pid: pid,
                processName: curCommand,
                user: curUser,
                proto: proto,
                ipFamily: curIPFamily,
                localAddress: addr,
                port: port,
                state: curState
            ))
            curFd = ""; curProto = nil; curIPFamily = nil; curName = ""; curState = nil
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = raw.first else { continue }
            let rest = String(raw.dropFirst())
            switch first {
            case "p":
                flushFd()
                curPid = Int32(rest)
                curCommand = ""; curUser = ""
                curFd = ""; curProto = nil; curIPFamily = nil; curName = ""; curState = nil
            case "c": curCommand = rest
            case "L": curUser = rest
            case "u": continue // UID — ignored; prefer "L" login name
            case "f":
                flushFd()
                curFd = rest
            case "P":
                if rest == "TCP" { curProto = .tcp }
                else if rest == "UDP" { curProto = .udp }
            case "t":
                if rest == "IPv4" { curIPFamily = .v4 }
                else if rest == "IPv6" { curIPFamily = .v6 }
            case "n": curName = rest
            case "T":
                if rest.hasPrefix("ST=") { curState = String(rest.dropFirst(3)) }
            default: continue
            }
        }
        flushFd()
        return result
    }

    /// "127.0.0.1:3000" → ("127.0.0.1", 3000)
    /// "[::1]:8443"     → ("[::1]", 8443)
    /// "*:5432"         → ("*", 5432)
    private func splitAddrPort(_ s: String) -> (String, UInt16)? {
        if let bracketEnd = s.firstIndex(of: "]") {
            let addr = String(s[...bracketEnd])
            let afterBracket = s.index(after: bracketEnd)
            guard afterBracket < s.endIndex, s[afterBracket] == ":" else { return nil }
            let port = String(s[s.index(after: afterBracket)...])
            guard let p = UInt16(port) else { return nil }
            return (addr, p)
        } else {
            guard let colon = s.lastIndex(of: ":") else { return nil }
            let addr = String(s[..<colon])
            let port = String(s[s.index(after: colon)...])
            guard let p = UInt16(port) else { return nil }
            return (addr, p)
        }
    }
}
