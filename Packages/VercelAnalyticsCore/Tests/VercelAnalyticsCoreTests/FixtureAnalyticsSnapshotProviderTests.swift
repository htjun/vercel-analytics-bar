import Testing
import VercelAnalyticsCore

@Test func fixtureProviderReturnsItsSnapshot() async throws {
    let expected = AnalyticsSnapshot.fixture
    let provider = FixtureAnalyticsSnapshotProvider(value: expected)

    let snapshot = try await provider.snapshot(for: .last7Days)

    #expect(snapshot == expected)
    #expect(snapshot.projectName == "Acme Storefront")
    #expect(snapshot.primaryMetric.value == 12847)
    #expect(snapshot.pageViews.value == 21490)
    guard case let .percentage(change) = snapshot.visitors.comparison else {
        Issue.record("Expected a percentage comparison")
        return
    }
    #expect(abs(change - 13.49) < 0.01)
}

@Test func metricComparisonHandlesNoPreviousTraffic() {
    let noTraffic = AnalyticsMetric(label: "Visitors", value: 0, previousValue: 0)
    let newTraffic = AnalyticsMetric(label: "Visitors", value: 10, previousValue: 0)

    #expect(noTraffic.comparison == .percentage(0))
    #expect(newTraffic.comparison == .new)
}
