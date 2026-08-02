import Testing
@testable import VercelAnalyticsBar

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
