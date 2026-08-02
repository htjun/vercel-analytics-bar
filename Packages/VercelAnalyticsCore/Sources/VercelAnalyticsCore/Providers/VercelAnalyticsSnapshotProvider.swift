import Foundation

public struct VercelAnalyticsSnapshotProvider: AnalyticsSnapshotProviding {
    private let client: VercelAPIClient
    private let project: VercelProject
    private let now: @Sendable () -> Date

    public init(
        token: String,
        project: VercelProject,
        now: @escaping @Sendable () -> Date = Date.init,
        baseURL: URL = VercelAPIClient.defaultBaseURL,
        transport: any VercelHTTPTransport = URLSessionVercelHTTPTransport()
    ) {
        client = VercelAPIClient(token: token, baseURL: baseURL, transport: transport)
        self.project = project
        self.now = now
    }

    public func snapshot(for range: VercelAnalyticsRange) async throws -> AnalyticsSnapshot {
        let refreshedAt = now()
        async let currentCount = client.fetchCount(
            for: project,
            range: range,
            now: refreshedAt
        )
        async let previousCount = client.fetchCount(
            for: project,
            range: range,
            now: refreshedAt.addingTimeInterval(-range.duration)
        )
        async let series = client.fetchSeries(
            for: project,
            range: range,
            now: refreshedAt
        )

        let (count, previous, points) = try await (currentCount, previousCount, series)
        let last24HoursVisitors: Int = if range == .last24Hours {
            count.visitors
        } else {
            try await client.fetchCount(
                for: project,
                range: .last24Hours,
                now: refreshedAt
            ).visitors
        }

        return AnalyticsSnapshot(
            projectName: project.name,
            range: range,
            visitors: AnalyticsMetric(
                label: "Visitors",
                value: count.visitors,
                previousValue: previous.visitors
            ),
            pageViews: AnalyticsMetric(
                label: "Page Views",
                value: count.pageViews,
                previousValue: previous.pageViews
            ),
            series: points.points,
            last24HoursVisitors: last24HoursVisitors,
            refreshedAt: refreshedAt
        )
    }
}
