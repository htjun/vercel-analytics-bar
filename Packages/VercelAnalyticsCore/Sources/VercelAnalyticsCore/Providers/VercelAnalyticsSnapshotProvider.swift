import Foundation

private struct SnapshotData {
    let visitors: AnalyticsMetric
    let pageViews: AnalyticsMetric
    let series: [VercelAnalyticsPoint]
    let topPages: [VercelAnalyticsBreakdown]
    let topReferrers: [VercelAnalyticsBreakdown]
    let last24HoursVisitors: Int
}

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
        switch range {
        case .last24Hours:
            return try await snapshotForLast24Hours(refreshedAt: refreshedAt)
        case .last7Days, .last30Days:
            return try await snapshotForCompletedDays(range: range, refreshedAt: refreshedAt)
        }
    }

    private func snapshotForLast24Hours(refreshedAt: Date) async throws -> AnalyticsSnapshot {
        async let currentSeries = client.fetchSeries(
            for: project,
            range: .last24Hours,
            now: refreshedAt
        )
        async let previousSeries = client.fetchSeries(
            for: project,
            range: .last24Hours,
            now: refreshedAt.addingTimeInterval(-VercelAnalyticsRange.last24Hours.duration)
        )
        async let topPages = client.fetchTopBreakdown(
            for: project,
            dimension: .requestPath,
            range: .last24Hours,
            now: refreshedAt
        )
        async let topReferrers = client.fetchTopBreakdown(
            for: project,
            dimension: .referrerHostname,
            range: .last24Hours,
            now: refreshedAt
        )

        let (current, previous, pages, referrers) = try await (
            currentSeries,
            previousSeries,
            topPages,
            topReferrers
        )
        let currentTotals = totals(from: current)
        let previousTotals = totals(from: previous)
        let data = SnapshotData(
            visitors: AnalyticsMetric(
                label: "Visitors",
                value: currentTotals.visitors,
                previousValue: previousTotals.visitors
            ),
            pageViews: AnalyticsMetric(
                label: "Page Views",
                value: currentTotals.pageViews,
                previousValue: previousTotals.pageViews
            ),
            series: current.points,
            topPages: pages,
            topReferrers: referrers,
            last24HoursVisitors: currentTotals.visitors
        )

        return makeSnapshot(range: .last24Hours, data: data, refreshedAt: refreshedAt)
    }

    private func snapshotForCompletedDays(
        range: VercelAnalyticsRange,
        refreshedAt: Date
    ) async throws -> AnalyticsSnapshot {
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
        async let currentSeries = client.fetchSeries(
            for: project,
            range: range,
            now: refreshedAt
        )
        async let last24HoursSeries = client.fetchSeries(
            for: project,
            range: .last24Hours,
            now: refreshedAt
        )
        async let topPages = client.fetchTopBreakdown(
            for: project,
            dimension: .requestPath,
            range: range,
            now: refreshedAt
        )
        async let topReferrers = client.fetchTopBreakdown(
            for: project,
            dimension: .referrerHostname,
            range: range,
            now: refreshedAt
        )

        let (count, previous, series, last24, pages, referrers) = try await (
            currentCount,
            previousCount,
            currentSeries,
            last24HoursSeries,
            topPages,
            topReferrers
        )
        let data = SnapshotData(
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
            series: series.points,
            topPages: pages,
            topReferrers: referrers,
            last24HoursVisitors: totals(from: last24).visitors
        )

        return makeSnapshot(range: range, data: data, refreshedAt: refreshedAt)
    }

    private func totals(from series: VercelAnalyticsSeries) -> (visitors: Int, pageViews: Int) {
        series.points.reduce(into: (visitors: 0, pageViews: 0)) { totals, point in
            totals.visitors += point.visitors
            totals.pageViews += point.pageViews
        }
    }

    private func makeSnapshot(
        range: VercelAnalyticsRange,
        data: SnapshotData,
        refreshedAt: Date
    ) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            projectName: project.name,
            range: range,
            visitors: data.visitors,
            pageViews: data.pageViews,
            series: data.series,
            topPages: data.topPages,
            topReferrers: data.topReferrers,
            last24HoursVisitors: data.last24HoursVisitors,
            refreshedAt: refreshedAt
        )
    }
}
