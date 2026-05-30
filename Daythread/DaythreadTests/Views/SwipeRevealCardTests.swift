//
//  SwipeRevealCardTests.swift
//  DaythreadTests
//
//  Tests for:
//  • SwipeRevealSnap.resolveOpenState — panel open/close decision from gesture end state.
//  • GestureHostView.hitTest — pass-through of taps to circle buttons when panel is open.
//

import XCTest
@testable import Daythread

@MainActor
final class SwipeRevealCardTests: XCTestCase {

    // MARK: — resolveOpenState

    // Fast leftward flick: open regardless of current position.
    func test_fastLeftFlick_opensPanel() {
        XCTAssertTrue(
            SwipeRevealSnap.resolveOpenState(offset: -10, velocityX: -400, revealWidth: 216)
        )
    }

    // Fast leftward flick from fully-closed position: still opens.
    func test_fastLeftFlick_fromClosed_opensPanel() {
        XCTAssertTrue(
            SwipeRevealSnap.resolveOpenState(offset: 0, velocityX: -301, revealWidth: 216)
        )
    }

    // Fast rightward flick: close regardless of current position.
    func test_fastRightFlick_closesPanel() {
        XCTAssertFalse(
            SwipeRevealSnap.resolveOpenState(offset: -200, velocityX: 400, revealWidth: 216)
        )
    }

    // Slow release past midpoint (>108 pt): open.
    func test_slowRelease_pastMidpoint_opensPanel() {
        XCTAssertTrue(
            SwipeRevealSnap.resolveOpenState(offset: -109, velocityX: 50, revealWidth: 216)
        )
    }

    // Slow release exactly at midpoint: close (not past, use closed-side default).
    func test_slowRelease_atMidpoint_closesPanel() {
        XCTAssertFalse(
            SwipeRevealSnap.resolveOpenState(offset: -108, velocityX: 0, revealWidth: 216)
        )
    }

    // Slow release before midpoint: close.
    func test_slowRelease_beforeMidpoint_closesPanel() {
        XCTAssertFalse(
            SwipeRevealSnap.resolveOpenState(offset: -50, velocityX: 20, revealWidth: 216)
        )
    }

    // No movement at all: close.
    func test_atRest_noSwipe_closesPanel() {
        XCTAssertFalse(
            SwipeRevealSnap.resolveOpenState(offset: 0, velocityX: 0, revealWidth: 216)
        )
    }

    // Boundary: exactly one point past midpoint.
    func test_onePointPastMidpoint_opensPanel() {
        XCTAssertTrue(
            SwipeRevealSnap.resolveOpenState(offset: -109, velocityX: 0, revealWidth: 216)
        )
    }

    // Boundary: velocity exactly at threshold (300) — not fast enough, use position.
    func test_velocityAtThreshold_usesPositionRule() {
        // Offset is before midpoint → close even at exactly 300 pt/s
        XCTAssertFalse(
            SwipeRevealSnap.resolveOpenState(offset: -50, velocityX: -300, revealWidth: 216)
        )
        // Offset is past midpoint → open at exactly 300 pt/s
        XCTAssertTrue(
            SwipeRevealSnap.resolveOpenState(offset: -120, velocityX: -300, revealWidth: 216)
        )
    }

    // Different revealWidth: midpoint scales correctly.
    func test_customRevealWidth_midpointScales() {
        // revealWidth = 144, midpoint = 72
        XCTAssertTrue(
            SwipeRevealSnap.resolveOpenState(offset: -73, velocityX: 0, revealWidth: 144)
        )
        XCTAssertFalse(
            SwipeRevealSnap.resolveOpenState(offset: -72, velocityX: 0, revealWidth: 144)
        )
    }

    // MARK: — GestureHostView.hitTest

    private func makeView(width: CGFloat = 270, height: CGFloat = 80) -> GestureHostView {
        let v = GestureHostView()
        v.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return v
    }

    // When closed, hitTest returns self for any point within bounds.
    func test_hitTest_whenClosed_returnsViewForPointInBounds() {
        let view = makeView()
        view.isOpen = false
        view.revealWidth = 216

        // Leading edge of button area
        let result = view.hitTest(CGPoint(x: 54, y: 40), with: nil)
        XCTAssertEqual(result, view)
    }

    // When closed, hitTest returns self for the trailing (button) area too.
    func test_hitTest_whenClosed_returnsViewForButtonAreaPoint() {
        let view = makeView()
        view.isOpen = false
        view.revealWidth = 216

        let result = view.hitTest(CGPoint(x: 200, y: 40), with: nil)
        XCTAssertEqual(result, view)
    }

    // When open, hitTest returns nil for a point inside the button strip.
    func test_hitTest_whenOpen_returnsNilForButtonAreaPoint() {
        let view = makeView()
        view.isOpen = true
        view.revealWidth = 216

        // 54 = 270 - 216; any x >= 54 is in the button strip
        let result = view.hitTest(CGPoint(x: 100, y: 40), with: nil)
        XCTAssertNil(result)
    }

    // When open, hitTest returns nil even at the exact button-strip boundary.
    func test_hitTest_whenOpen_returnsNilAtButtonStripBoundary() {
        let view = makeView()
        view.isOpen = true
        view.revealWidth = 216

        let boundary = view.bounds.width - view.revealWidth  // 54
        let result = view.hitTest(CGPoint(x: boundary, y: 40), with: nil)
        XCTAssertNil(result)
    }

    // When open, hitTest returns self for a point in the card area (left of buttons).
    func test_hitTest_whenOpen_returnsViewForCardAreaPoint() {
        let view = makeView()
        view.isOpen = true
        view.revealWidth = 216

        // x = 30 is in the card area (0 to 54), not the button strip
        let result = view.hitTest(CGPoint(x: 30, y: 40), with: nil)
        XCTAssertEqual(result, view)
    }

    // When open, a point one pixel before the button strip is still card area.
    func test_hitTest_whenOpen_onePixelBeforeBoundary_returnsView() {
        let view = makeView()
        view.isOpen = true
        view.revealWidth = 216

        let justBeforeBoundary = view.bounds.width - view.revealWidth - 1  // 53
        let result = view.hitTest(CGPoint(x: justBeforeBoundary, y: 40), with: nil)
        XCTAssertEqual(result, view)
    }

    // Point completely outside bounds always returns nil (UIView default).
    func test_hitTest_outsideBounds_returnsNil() {
        let view = makeView()
        view.isOpen = false

        let result = view.hitTest(CGPoint(x: 400, y: 40), with: nil)
        XCTAssertNil(result)
    }

    // Open state with full revealWidth (entire view is button strip): all nil.
    func test_hitTest_whenOpen_fullRevealWidth_allNil() {
        let view = makeView(width: 216)
        view.isOpen = true
        view.revealWidth = 216

        let result = view.hitTest(CGPoint(x: 10, y: 40), with: nil)
        XCTAssertNil(result)
    }
}
