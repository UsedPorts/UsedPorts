import XCTest
import AppKit
@testable import UsedPorts

@MainActor
final class PortOutlineViewTests: XCTestCase {
    func test_horizontalScroller_sitsBelowRowsEvenWhenOverlayIsRequested() throws {
        let scroll = LegacyScrollerScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 1000))
        // Ask for overlay explicitly so the test doesn't depend on this machine's
        // scroller preference (a plain NSScrollView passes on a legacy-preferring Mac).
        scroll.scrollerStyle = .overlay
        scroll.tile()

        let scroller = try XCTUnwrap(scroll.horizontalScroller)
        // The scroller's own style, not our overridden getter.
        XCTAssertEqual(scroller.scrollerStyle, .legacy)
        XCTAssertFalse(scroller.isHidden)
        // Visible rows end where the scroller begins: no overlap.
        XCTAssertFalse(scroll.contentView.frame.intersects(scroller.frame),
                       "content \(scroll.contentView.frame) overlaps scroller \(scroller.frame)")
    }
}
