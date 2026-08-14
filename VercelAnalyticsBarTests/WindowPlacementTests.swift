import AppKit
import SwiftUI
import Testing
@testable import VercelAnalyticsBar

@Test func adjacentWindowPlacementUsesTheSideWithEnoughSpace() {
    let size = CGSize(width: 520, height: 680)
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    let leftFrame = AdjacentWindowPlacement.frame(
        anchor: CGRect(x: 1000, y: 300, width: 400, height: 562),
        windowSize: size,
        visibleFrame: visibleFrame
    )
    #expect(leftFrame == CGRect(x: 468, y: 182, width: 520, height: 680))

    let rightFrame = AdjacentWindowPlacement.frame(
        anchor: CGRect(x: 20, y: 200, width: 400, height: 562),
        windowSize: size,
        visibleFrame: visibleFrame
    )
    #expect(rightFrame == CGRect(x: 432, y: 82, width: 520, height: 680))
}

@Test func adjacentWindowPlacementPrefersMoreSpaceAndBreaksTiesToTheRight() {
    let size = CGSize(width: 480, height: 600)
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    let moreSpaceOnRight = AdjacentWindowPlacement.frame(
        anchor: CGRect(x: 500, y: 250, width: 400, height: 562),
        windowSize: size,
        visibleFrame: visibleFrame
    )
    #expect(moreSpaceOnRight.origin.x == 912)

    let equalSpace = AdjacentWindowPlacement.frame(
        anchor: CGRect(x: 520, y: 250, width: 400, height: 562),
        windowSize: size,
        visibleFrame: visibleFrame
    )
    #expect(equalSpace.origin.x == 932)
}

@Test func adjacentWindowPlacementClampsAndSupportsOffsetDisplays() {
    let frame = AdjacentWindowPlacement.frame(
        anchor: CGRect(x: -450, y: 450, width: 400, height: 562),
        windowSize: CGSize(width: 520, height: 680),
        visibleFrame: CGRect(x: -1600, y: 100, width: 1600, height: 900)
    )

    #expect(frame == CGRect(x: -982, y: 312, width: 520, height: 680))
}

@Test func adjacentWindowPlacementCentersWhenNeitherSideFits() {
    let frame = AdjacentWindowPlacement.frame(
        anchor: CGRect(x: 300, y: 120, width: 400, height: 562),
        windowSize: CGSize(width: 520, height: 680),
        visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
    )

    #expect(frame == CGRect(x: 240, y: 60, width: 520, height: 680))
}

@MainActor
@Test func hostedWindowControllerOnlyAppliesAdjacentPlacementOnce() throws {
    let controller = HostedWindowController(
        title: "Test Settings",
        contentSize: CGSize(width: 520, height: 680),
        rootView: EmptyView()
    )
    let window = try #require(controller.window)
    let firstContext = AdjacentWindowPresentationContext(
        anchorFrame: CGRect(x: 1000, y: 300, width: 400, height: 562),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
    )
    controller.present(adjacentTo: firstContext)
    let initiallyPlacedFrame = window.frame
    #expect(initiallyPlacedFrame.maxX == firstContext.anchorFrame.minX - AdjacentWindowPlacement.gap)

    let movedOrigin = CGPoint(x: 120, y: 140)
    window.setFrameOrigin(movedOrigin)
    window.orderOut(nil)
    controller.present(adjacentTo: AdjacentWindowPresentationContext(
        anchorFrame: CGRect(x: 20, y: 200, width: 400, height: 562),
        visibleFrame: firstContext.visibleFrame
    ))

    #expect(window.frame.origin == movedOrigin)
    window.orderOut(nil)
}
