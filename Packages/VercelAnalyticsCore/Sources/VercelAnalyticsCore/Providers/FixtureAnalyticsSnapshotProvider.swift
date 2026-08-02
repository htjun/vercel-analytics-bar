import Foundation

public struct FixtureAnalyticsSnapshotProvider: AnalyticsSnapshotProviding {
    public let value: AnalyticsSnapshot

    public init(value: AnalyticsSnapshot = .fixture) {
        self.value = value
    }

    public func snapshot() async throws -> AnalyticsSnapshot {
        value
    }
}

public extension AnalyticsSnapshot {
    private static let fixtureRefreshDate = Date(timeIntervalSince1970: 1_785_549_600)

    static let fixture = AnalyticsSnapshot(
        projectName: "Acme Storefront",
        primaryMetric: AnalyticsMetric(label: "Visitors", value: 12847),
        refreshedAt: fixtureRefreshDate
    )
}
