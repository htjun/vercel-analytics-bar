import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

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
