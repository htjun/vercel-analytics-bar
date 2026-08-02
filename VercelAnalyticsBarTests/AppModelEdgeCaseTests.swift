import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelShowsEmptyStateWhenNoProjectIsSelected() async {
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: []) },
        analyticsProviderFactory: { _, _ in FixtureAnalyticsSnapshotProvider() },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    await model.load()

    #expect(model.state == .empty("Select a Vercel project in Settings to load analytics."))
}
