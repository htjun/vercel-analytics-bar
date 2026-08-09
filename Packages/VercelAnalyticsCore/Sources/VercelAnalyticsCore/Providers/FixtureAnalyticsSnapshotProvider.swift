import Foundation

public struct FixtureAnalyticsSnapshotProvider: AnalyticsSnapshotProviding {
    public let value: AnalyticsSnapshot

    public init(value: AnalyticsSnapshot = .fixture) {
        self.value = value
    }

    public func snapshot(for _: VercelAnalyticsRange) async throws -> AnalyticsSnapshot {
        value
    }
}

public extension AnalyticsSnapshot {
    private static let fixtureRefreshDate = Date(timeIntervalSince1970: 1_785_549_600)

    static let fixture = AnalyticsSnapshot(
        projectName: "Acme Storefront",
        range: .last7Days,
        visitors: AnalyticsMetric(label: "Visitors", value: 12847, previousValue: 11320),
        pageViews: AnalyticsMetric(label: "Page Views", value: 21490, previousValue: 20115),
        series: [
            VercelAnalyticsPoint(
                timestamp: Date(timeIntervalSince1970: 1_785_463_200),
                visitors: 1720,
                pageViews: 2950
            ),
            VercelAnalyticsPoint(
                timestamp: fixtureRefreshDate,
                visitors: 1890,
                pageViews: 3170
            ),
        ],
        topPages: [
            VercelAnalyticsBreakdown(label: "/products", visitors: 820, pageViews: 1280),
            VercelAnalyticsBreakdown(label: "/pricing", visitors: 615, pageViews: 940),
        ],
        topReferrers: [
            VercelAnalyticsBreakdown(label: "google.com", visitors: 510, pageViews: 640),
            VercelAnalyticsBreakdown(label: "news.ycombinator.com", visitors: 205, pageViews: 260),
        ],
        last24HoursVisitors: 1890,
        refreshedAt: fixtureRefreshDate
    )
}
