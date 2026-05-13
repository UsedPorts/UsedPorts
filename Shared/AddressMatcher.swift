import Foundation
import Darwin

/// Matches an entry's local address against a user-supplied filter query.
///
/// Query syntax:
///   - Comma-separated list of tokens (OR semantics across tokens).
///   - Each token may be:
///       * A CIDR block (e.g. `192.168.1.0/24`, `fe80::/16`)
///       * A single IP literal (exact match, case-insensitive for IPv6).
///       * Any other text → substring match against the raw address.
///   - Empty query (or only whitespace) matches everything.
///
/// Entry-side normalization:
///   - `*` (lsof wildcard) is treated as `0.0.0.0`.
///   - Surrounding brackets in `[::1]`-style IPv6 are stripped.
public struct AddressMatcher {
    public static func matches(localAddress: String, query: String) -> Bool {
        let tokens = query
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return true }
        let normalized = normalize(localAddress)
        return tokens.contains { token in
            match(normalizedAddr: normalized, token: token, raw: localAddress)
        }
    }

    /// Normalizes address strings, e.g. `*` → "0.0.0.0", `[::1]` → "::1".
    static func normalize(_ s: String) -> String {
        if s == "*" { return "0.0.0.0" }
        var t = s
        if t.hasPrefix("[") && t.hasSuffix("]") {
            t.removeFirst()
            t.removeLast()
        }
        return t
    }

    private static func match(normalizedAddr: String, token: String, raw: String) -> Bool {
        // CIDR?
        if let slash = token.firstIndex(of: "/") {
            let base = String(token[..<slash])
            let prefStr = String(token[token.index(after: slash)...])
            if let pref = Int(prefStr),
               let result = cidrMatch(addr: normalizedAddr, base: base, prefix: pref) {
                return result
            }
            return false
        }
        // Return true on an exact match against a single IP literal; otherwise fall back to substring.
        if let result = ipExact(addr: normalizedAddr, ip: token), result {
            return true
        }
        // Substring fallback (against the raw string)
        return raw.localizedCaseInsensitiveContains(token)
    }

    private static func ipExact(addr: String, ip: String) -> Bool? {
        if let a = parseIPv4(addr), let b = parseIPv4(ip) { return a == b }
        if let a = parseIPv6(addr), let b = parseIPv6(ip) { return a == b }
        return nil
    }

    private static func cidrMatch(addr: String, base: String, prefix: Int) -> Bool? {
        if let a = parseIPv4(addr), let b = parseIPv4(base) {
            guard (0...32).contains(prefix) else { return false }
            let mask: UInt32 = prefix == 0 ? 0 : (~UInt32(0)) << (32 - prefix)
            return (a & mask) == (b & mask)
        }
        if let a = parseIPv6(addr), let b = parseIPv6(base) {
            guard (0...128).contains(prefix) else { return false }
            var mask = [UInt8](repeating: 0, count: 16)
            var remaining = prefix
            for i in 0..<16 {
                if remaining >= 8 {
                    mask[i] = 0xFF
                    remaining -= 8
                } else if remaining > 0 {
                    mask[i] = UInt8(0xFF << (8 - remaining))
                    remaining = 0
                } else {
                    mask[i] = 0
                }
            }
            for i in 0..<16 {
                if (a[i] & mask[i]) != (b[i] & mask[i]) { return false }
            }
            return true
        }
        return nil
    }

    static func parseIPv4(_ s: String) -> UInt32? {
        var addr = in_addr()
        if inet_pton(AF_INET, s, &addr) == 1 {
            return UInt32(bigEndian: addr.s_addr)
        }
        return nil
    }

    static func parseIPv6(_ s: String) -> [UInt8]? {
        var addr = in6_addr()
        if inet_pton(AF_INET6, s, &addr) == 1 {
            let bytes = withUnsafeBytes(of: &addr) { Array($0.bindMemory(to: UInt8.self)) }
            return Array(bytes.prefix(16))
        }
        return nil
    }
}
