import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@Test func analyticsPanelPlacementCentersAndClampsToTheVisibleScreen() {
    let size = AnalyticsCardLayout.rootSize
    let visibleFrame = CGRect(x: 100, y: 50, width: 1200, height: 800)

    let centered = AnalyticsPanelPlacement.frame(
        anchor: CGRect(x: 680, y: 850, width: 40, height: 24),
        panelSize: size,
        visibleFrame: visibleFrame
    )
    #expect(centered == CGRect(x: 500, y: 284, width: 400, height: 562))

    let leftClamped = AnalyticsPanelPlacement.frame(
        anchor: CGRect(x: 90, y: 850, width: 40, height: 24),
        panelSize: size,
        visibleFrame: visibleFrame
    )
    #expect(leftClamped.minX == 108)

    let rightClamped = AnalyticsPanelPlacement.frame(
        anchor: CGRect(x: 1280, y: 850, width: 40, height: 24),
        panelSize: size,
        visibleFrame: visibleFrame
    )
    #expect(rightClamped.maxX == 1292)

    let shadowFrame = AnalyticsPanelPlacement.shadowFrame(forGlassFrame: centered)
    #expect(shadowFrame.insetBy(
        dx: AnalyticsCardLayout.panelShadowPadding,
        dy: AnalyticsCardLayout.panelShadowPadding
    ) == centered)
}

@Test func analyticsPanelPlacementUsesTheProvidedDisplayCoordinates() {
    let frame = AnalyticsPanelPlacement.frame(
        anchor: CGRect(x: -900, y: 1080, width: 80, height: 24),
        panelSize: AnalyticsCardLayout.rootSize,
        visibleFrame: CGRect(x: -1440, y: 0, width: 1440, height: 1080)
    )

    #expect(frame == CGRect(x: -1060, y: 514, width: 400, height: 562))
}

@Test func statusItemPresentationDescribesLoadedAndUnavailableStates() {
    let unavailable = StatusItemPresentation(abbreviatedVisitors: nil)
    #expect(unavailable.title.isEmpty)
    #expect(unavailable.accessibilityValue == "Visitor data unavailable")
    #expect(unavailable.toolTip == "Vercel Analytics Bar")

    let loaded = StatusItemPresentation(abbreviatedVisitors: "1.8K")
    #expect(loaded.title == "1.8K")
    #expect(loaded.accessibilityValue == "1.8K visitors in the last 24 hours")
    #expect(loaded.toolTip == "Vercel Analytics Bar — 1.8K visitors")
}

@MainActor
@Test func statusBarControllerMakesItsStatusItemVisibleOnLaunch() {
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: InMemoryLaunchAtLoginManager()
    )
    let controller = StatusBarController(
        model: model,
        componentStyle: ComponentStyleStore()
    )
    defer { controller.tearDown() }

    #expect(controller.isStatusItemVisible)
}

@MainActor
@Test func analyticsPanelControllerOwnsPresentationThroughDismissal() {
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: InMemoryLaunchAtLoginManager()
    )
    var highlightStates: [Bool] = []
    let controller = AnalyticsPanelController(
        model: model,
        componentStyle: ComponentStyleStore(),
        setStatusItemHighlighted: { highlightStates.append($0) }
    )
    let anchor = AnalyticsPanelAnchor(
        frame: CGRect(x: 680, y: 850, width: 40, height: 24),
        visibleFrame: CGRect(x: 100, y: 50, width: 1200, height: 800)
    )
    let changedAnchor = AnalyticsPanelAnchor(
        frame: CGRect(x: 1100, y: 850, width: 40, height: 24),
        visibleFrame: anchor.visibleFrame
    )
    let initialSessionID = controller.sessionID

    controller.present(anchor: anchor)
    let presentedSessionID = controller.sessionID
    let presentedFrame = controller.window.frame
    let presentedShadowFrame = controller.window.shadowWindow.frame
    #expect(controller.isPresented)
    #expect(presentedSessionID != initialSessionID)
    expectPanelFrames(controller, equalTo: CGRect(x: 500, y: 284, width: 400, height: 562))
    #expect(highlightStates == [true])
    #expect(controller.hasLocalEventMonitor)
    #expect(controller.hasGlobalEventMonitor)

    controller.present(anchor: changedAnchor)
    #expect(controller.sessionID == presentedSessionID)
    #expect(controller.window.frame == presentedFrame)
    #expect(controller.window.shadowWindow.frame == presentedShadowFrame)
    #expect(highlightStates == [true])

    let transientChild = NSWindow()
    controller.window.addChildWindow(transientChild, ordered: .above)
    transientChild.orderFrontRegardless()
    controller.dismiss()

    #expect(!controller.isPresented)
    #expect(!transientChild.isVisible)
    #expect(!controller.window.isVisible)
    #expect(highlightStates == [true, false])
    #expect(!controller.hasLocalEventMonitor)
    #expect(!controller.hasGlobalEventMonitor)

    controller.present(anchor: changedAnchor)
    #expect(controller.sessionID != presentedSessionID)
    expectPanelFrames(controller, equalTo: CGRect(x: 892, y: 284, width: 400, height: 562))
    controller.tearDown()
}

@MainActor
private func expectPanelFrames(_ controller: AnalyticsPanelController, equalTo glassFrame: CGRect) {
    #expect(controller.window.frame == glassFrame)
    #expect(controller.window.shadowWindow.frame == AnalyticsPanelPlacement.shadowFrame(
        forGlassFrame: glassFrame
    ))
}

@MainActor
@Test func analyticsPanelHasOnlyTheCustomTransparentChrome() {
    let panel = AnalyticsPanel(hostingView: NSView())

    #expect(panel.frame.size == AnalyticsCardLayout.rootSize)
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    #expect(!panel.isOpaque)
    #expect(panel.backgroundColor == .clear)
    #expect(!panel.hasShadow)
    #expect(panel.shadowWindow.frame.size == AnalyticsCardLayout.panelShadowWindowSize)
    #expect(panel.shadowWindow.ignoresMouseEvents)
    #expect(panel.shadowWindow.parent === panel)
    #expect(panel.shadowWindow.shadowView.shadowLayer.shadowOpacity == 0.03)
    #expect(panel.shadowWindow.shadowView.shadowLayer.shadowRadius == 12)
    #expect(panel.shadowWindow.shadowView.shadowLayer.shadowOffset == CGSize(width: 0, height: -2))
    #expect(panel.shadowWindow.shadowView.shadowLayer.shadowPath != nil)
    #expect(panel.materialView === panel.contentView)
    #expect(panel.level == .popUpMenu)
    #expect(panel.canBecomeKey)
    #expect(!panel.canBecomeMain)

    if let materialView = panel.materialView as? NSVisualEffectView {
        #expect(materialView.material == .underWindowBackground)
        #expect(materialView.blendingMode == .behindWindow)
        #expect(materialView.state == .active)
    }

    #if compiler(>=6.2)
        if #available(macOS 26, *) {
            #expect((panel.materialView as? NSGlassEffectView)?.style == .clear)
        }
    #else
        #expect(panel.materialView is NSVisualEffectView)
    #endif
}

@MainActor
@Test func appDelegateKeepsRunningAfterTheLastWindowCloses() {
    let appDelegate = AppDelegate()

    #expect(!appDelegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
}

@MainActor
@Test func applicationMenuProvidesNativeCommands() throws {
    let application = NSApplication.shared
    let mainMenu = ApplicationMenu.make(for: application)
    let applicationMenu = try #require(mainMenu.items.first?.submenu)
    let quitItem = try #require(applicationMenu.items.first)
    let editMenu = try #require(mainMenu.items.last?.submenu)

    #expect(mainMenu.items.count == 2)
    #expect(applicationMenu.title == ProductInfo.name)
    #expect(applicationMenu.items.count == 1)
    #expect(quitItem.title == "Quit \(ProductInfo.name)")
    #expect(quitItem.action == #selector(NSApplication.terminate(_:)))
    #expect(quitItem.target === application)
    #expect(quitItem.keyEquivalent == "q")
    #expect(quitItem.keyEquivalentModifierMask == .command)

    #expect(editMenu.title == "Edit")
    #expect(editMenu.items.map(\.title) == ["Undo", "Redo", "", "Cut", "Copy", "Paste", "Select All"])

    let pasteItem = try #require(editMenu.items.first { $0.action == #selector(NSText.paste(_:)) })
    #expect(pasteItem.target == nil)
    #expect(pasteItem.keyEquivalent == "v")
    #expect(pasteItem.keyEquivalentModifierMask == .command)
}

@MainActor
@Test func hostedWindowControllerRetainsAndReusesItsWindow() throws {
    let controller = HostedWindowController(
        title: "Test Settings",
        contentSize: CGSize(width: 520, height: 680),
        rootView: EmptyView()
    )
    let window = try #require(controller.window)

    #expect(window.title == "Test Settings")
    #expect(window.contentMinSize == CGSize(width: 520, height: 680))
    #expect(window.contentMaxSize == CGSize(width: 520, height: 680))
    #expect(!window.isReleasedWhenClosed)
    #expect(!window.styleMask.contains(.resizable))

    window.close()

    #expect(controller.window === window)
}

@MainActor
@Test func hostedWindowControllerSupportsResizableInspectorWindows() throws {
    let controller = HostedWindowController(
        title: "Chart Inspector",
        contentSize: CGSize(width: 820, height: 640),
        minimumContentSize: CGSize(width: 740, height: 560),
        isResizable: true,
        rootView: EmptyView()
    )
    let window = try #require(controller.window)

    #expect(window.styleMask.contains(.resizable))
    #expect(window.styleMask.contains(.miniaturizable))
    #expect(window.contentMinSize == CGSize(width: 740, height: 560))
}

@MainActor
@Test func analyticsPanelControllerKeepsOwnedWindowsOpenAndHandlesEscape() {
    let childWindow = NSWindow()
    let statusItemWindow = NSWindow()
    let companionWindow = NSWindow()
    let controller = makePanelController(
        statusItemWindow: statusItemWindow,
        companionWindows: [companionWindow]
    )
    controller.present(anchor: nil)
    controller.window.addChildWindow(childWindow, ordered: .above)
    childWindow.orderFrontRegardless()

    for eventWindow in [controller.window, childWindow, statusItemWindow, companionWindow] {
        #expect(controller.handle(.pointerDown(window: eventWindow)) == .passThrough)
        #expect(controller.isPresented)
    }

    #expect(controller.handle(.escape) == .passThrough)
    #expect(controller.isPresented)
    childWindow.orderOut(nil)
    #expect(controller.handle(.escape) == .consume)
    #expect(!controller.isPresented)
    controller.tearDown()
}

@MainActor
@Test func analyticsPanelControllerDismissesForOutsideAndGlobalEvents() {
    let controller = makePanelController()
    controller.present(anchor: nil)

    #expect(controller.handle(.pointerDown(window: NSWindow())) == .passThrough)
    #expect(!controller.isPresented)

    controller.present(anchor: nil)
    #expect(controller.handle(.globalPointerDown) == .passThrough)
    #expect(!controller.isPresented)
    controller.tearDown()
}

@MainActor
private func makePanelController(
    statusItemWindow: NSWindow? = nil,
    companionWindows: [NSWindow] = []
) -> AnalyticsPanelController {
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: InMemoryLaunchAtLoginManager()
    )
    return AnalyticsPanelController(
        model: model,
        componentStyle: ComponentStyleStore(),
        setStatusItemHighlighted: { _ in },
        statusItemWindow: { statusItemWindow },
        companionWindows: { companionWindows }
    )
}

@MainActor
@Test func appModelManagesLaunchAtLoginThroughInjectedManager() {
    let manager = InMemoryLaunchAtLoginManager()
    let model = AppModel(
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: manager
    )

    #expect(model.launchAtLoginStatus == .disabled)

    model.setLaunchAtLogin(enabled: true)
    #expect(model.launchAtLoginStatus == .enabled)
    #expect(model.launchAtLoginError == nil)

    model.setLaunchAtLogin(enabled: false)
    #expect(model.launchAtLoginStatus == .disabled)
}

@MainActor
@Test func appModelSurfacesLaunchAtLoginFailureWithoutChangingState() {
    let manager = InMemoryLaunchAtLoginManager()
    manager.failure = .registrationFailed
    let model = AppModel(
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        launchAtLoginManager: manager
    )

    model.setLaunchAtLogin(enabled: true)

    #expect(model.launchAtLoginStatus == .disabled)
    #expect(model.launchAtLoginError == LaunchAtLoginError.registrationFailed.localizedDescription)
}

@MainActor
@Test func appModelManualRefreshDoesNotRequestAnalytics() async {
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let provider = ControlledSnapshotProvider()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in provider },
        launchAtLoginManager: InMemoryLaunchAtLoginManager(),
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    #expect(model.confirmProjectSelection([project.id]))
    await model.refreshProjects()
    #expect(model.projectState == .loaded([project]))
    #expect(await provider.requestedRanges.isEmpty)
    #expect(model.state == .idle)
}
