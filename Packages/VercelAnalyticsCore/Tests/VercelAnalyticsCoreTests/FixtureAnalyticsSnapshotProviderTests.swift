import Testing
import VercelAnalyticsCore

@Test func fixtureProviderReturnsItsSnapshot() async throws {
    let expected = AnalyticsSnapshot.fixture
    let provider = FixtureAnalyticsSnapshotProvider(value: expected)

    let snapshot = try await provider.snapshot()

    #expect(snapshot == expected)
    #expect(snapshot.projectName == "Acme Storefront")
    #expect(snapshot.primaryMetric.value == 12_847)
}
