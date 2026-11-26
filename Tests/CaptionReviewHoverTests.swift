import XCTest
import AppKit
@testable import AfterMeet

final class CaptionReviewHoverTests: XCTestCase {
    func testPreviewAboveBottomCaptionWithoutMovingOrCoveringIt() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caption = NSRect(x: 180, y: 30, width: 620, height: 56)
        let preview = CaptionReviewHoverController.frame(anchor: caption, screen: screen)
        XCTAssertEqual(preview.minY, caption.maxY + 8)
        XCTAssertTrue(screen.contains(preview))
        XCTAssertFalse(preview.intersects(caption))
    }
    func testPreviewBelowTopCaption() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let caption = NSRect(x: 1000, y: 800, width: 420, height: 56)
        let preview = CaptionReviewHoverController.frame(anchor: caption, screen: screen)
        XCTAssertEqual(preview.maxY, caption.minY - 8)
        XCTAssertTrue(screen.contains(preview))
        XCTAssertFalse(preview.intersects(caption))
    }
    func testSecondaryDisplayWithNegativeOriginAndNarrowSpace() {
        let screen = NSRect(x: -800, y: -200, width: 800, height: 600)
        let caption = NSRect(x: -350, y: 20, width: 620, height: 56)
        let preview = CaptionReviewHoverController.frame(anchor: caption, screen: screen)
        XCTAssertTrue(screen.contains(preview))
        XCTAssertLessThanOrEqual(preview.maxX, screen.maxX - 12)
        XCTAssertFalse(preview.intersects(caption))
    }
    func testEmptyReviewUsesCompactHeight() {
        let frame = CaptionReviewHoverController.frame(
            anchor: NSRect(x: 100, y: 300, width: 320, height: 56),
            screen: NSRect(x: 0, y: 0, width: 1000, height: 800), preferredHeight: 180)
        XCTAssertEqual(frame.height, 180)
    }

    @MainActor
    func testDwellGapCrossingAndExitLifecycle() async throws {
        _ = NSApplication.shared
        let anchor = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 400, height: 56),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        anchor.orderFrontRegardless()
        let hover = CaptionReviewHoverController()
        defer { hover.dismiss(immediately: true); anchor.orderOut(nil) }
        hover.setCaptionHovered(true, anchor: anchor)
        hover.setCaptionHovered(false, anchor: anchor)
        try await Task.sleep(nanoseconds: 380_000_000)
        XCTAssertTrue(anchor.childWindows?.isEmpty ?? true, "Passing across the caption must not flash a preview")
        hover.setCaptionHovered(true, anchor: anchor)
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(anchor.childWindows?.count, 1)
        hover.setCaptionHovered(false, anchor: anchor)
        hover.setReviewHovered(true)
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(anchor.childWindows?.count, 1, "Reading in the preview must keep it open")
        hover.setReviewHovered(false)
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertTrue(anchor.childWindows?.isEmpty ?? true)
    }
}
