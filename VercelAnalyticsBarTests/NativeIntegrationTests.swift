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
    #expect(unavailable.toolTip == "Vercel Analytics")

    let loaded = StatusItemPresentation(abbreviatedVisitors: "1.8K")
    #expect(loaded.title == "1.8K")
    #expect(loaded.accessibilityValue == "1.8K visitors in the last 24 hours")
    #expect(loaded.toolTip == "Vercel Analytics — 1.8K visitors")
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
        chartStyle: ChartStyleStore(),
        onOpenSettings: {}
    )
    defer { controller.tearDown() }

    #expect(controller.isStatusItemVisible)
}

@Test func analyticsPanelPresentationResetsItsSessionWhenPresented() {
    var state = AnalyticsPanelPresentationState()
    let initialSessionID = state.sessionID

    state.present()
    #expect(state.isPresented)
    #expect(state.sessionID != initialSessionID)

    let presentedSessionID = state.sessionID
    state.dismiss()
    #expect(!state.isPresented)

    state.present()
    #expect(state.sessionID != presentedSessionID)
}

@MainActor
@Test func analyticsPanelHasOnlyTheCustomTransparentChrome() {
    let panel = AnalyticsPanel(hostingView: NSView())

    #expect(panel.frame.size == AnalyticsCardLayout.rootSize)
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
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
@Test func analyticsPanelEventPolicyKeepsOwnedAndStatusWindowsOpen() {
    let panel = AnalyticsPanel(hostingView: NSView())
    let childWindow = NSWindow()
    let statusItemWindow = NSWindow()
    let companionWindow = NSWindow()
    let unrelatedWindow = NSWindow()
    panel.addChildWindow(childWindow, ordered: .above)

    #expect(AnalyticsPanelEventPolicy.keepsPanelOpen(
        for: panel,
        panel: panel,
        statusItemWindow: statusItemWindow
    ))
    #expect(AnalyticsPanelEventPolicy.keepsPanelOpen(
        for: childWindow,
        panel: panel,
        statusItemWindow: statusItemWindow
    ))
    #expect(AnalyticsPanelEventPolicy.keepsPanelOpen(
        for: statusItemWindow,
        panel: panel,
        statusItemWindow: statusItemWindow
    ))
    #expect(AnalyticsPanelEventPolicy.keepsPanelOpen(
        for: companionWindow,
        panel: panel,
        statusItemWindow: statusItemWindow,
        companionWindows: [companionWindow]
    ))
    #expect(!AnalyticsPanelEventPolicy.keepsPanelOpen(
        for: unrelatedWindow,
        panel: panel,
        statusItemWindow: statusItemWindow
    ))
    #expect(!AnalyticsPanelEventPolicy.keepsPanelOpen(
        for: nil,
        panel: panel,
        statusItemWindow: statusItemWindow
    ))
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
@Test func appModelSyncNowRefreshesProjectsAndAnalytics() async {
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
    let syncTask = Task { await model.syncNow() }
    await provider.waitUntilRequested()
    #expect(model.projectState == .loaded([project]))

    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    await provider.succeed(with: snapshot)
    await syncTask.value

    #expect(model.state == .loaded(snapshot))
}
