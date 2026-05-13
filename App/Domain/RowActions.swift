import Foundation
import AppKit

public struct RowActions {
    public static func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    public static func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func isProtected(pid: Int32) -> Bool {
        let myPid = ProcessInfo.processInfo.processIdentifier
        return pid <= 1 || pid == myPid
    }
}
