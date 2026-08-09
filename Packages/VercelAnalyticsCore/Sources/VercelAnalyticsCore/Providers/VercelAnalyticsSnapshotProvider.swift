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
        let plan = range.plan(at: refreshedAt)
        switch plan.totalsSource {
        case .aggregate:
            return try await snapshotFromAggregateTotals(range: range, plan: plan, refreshedAt: refreshedAt)
        case .count:
            return try await snapshotFromCountTotals(range: range, plan: plan, refreshedAt: refreshedAt)
        }
    }

    private func snapshotFromAggregateTotals(
        range: VercelAnalyticsRange,
        plan: VercelAnalyticsRangePlan,
        refreshedAt: Date
    ) async throws -> AnalyticsSnapshot {
        async let currentSeries = client.fetchSeries(
            for: project,
            window: plan.currentWindow,
            bucket: plan.bucket
        )
        async let previousSeries = client.fetchSeries(
            for: project,
            window: plan.previousWindow,
            bucket: plan.bucket
        )
        async let topPages = client.fetchTopBreakdown(
            for: project,
            dimension: .requestPath,
            window: plan.currentWindow
        )
        async let topReferrers = client.fetchTopBreakdown(
            for: project,
            dimension: .referrerHostname,
            window: plan.currentWindow
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

        return makeSnapshot(range: range, data: data, refreshedAt: refreshedAt)
    }

    private func snapshotFromCountTotals(
        range: VercelAnalyticsRange,
        plan: VercelAnalyticsRangePlan,
        refreshedAt: Date
    ) async throws -> AnalyticsSnapshot {
        async let currentCount = client.fetchCount(
            for: project,
            window: plan.currentWindow
        )
        async let previousCount = client.fetchCount(
            for: project,
            window: plan.previousWindow
        )
        async let currentSeries = client.fetchSeries(
            for: project,
            window: plan.currentWindow,
            bucket: plan.bucket
        )
        let last24HoursPlan = VercelAnalyticsRange.last24Hours.plan(at: refreshedAt)
        async let last24HoursSeries = client.fetchSeries(
            for: project,
            window: last24HoursPlan.currentWindow,
            bucket: last24HoursPlan.bucket
        )
        async let topPages = client.fetchTopBreakdown(
            for: project,
            dimension: .requestPath,
            window: plan.currentWindow
        )
        async let topReferrers = client.fetchTopBreakdown(
            for: project,
            dimension: .referrerHostname,
            window: plan.currentWindow
        )

        let (count, previous, series, last24, pages, referrers) = try await (
            currentCount,
            previousCount,
            currentSeries,
            last24HoursSeries,
            topPages,
            topReferrers
        )
        let data = completedDaysData(
            count: count,
            previous: previous,
            series: series,
            last24: last24,
            breakdowns: (pages: pages, referrers: referrers)
        )

        return makeSnapshot(range: range, data: data, refreshedAt: refreshedAt)
    }

    private func completedDaysData(
        count: VercelAnalyticsCount,
        previous: VercelAnalyticsCount,
        series: VercelAnalyticsSeries,
        last24: VercelAnalyticsSeries,
        breakdowns: (pages: [VercelAnalyticsBreakdown], referrers: [VercelAnalyticsBreakdown])
    ) -> SnapshotData {
        SnapshotData(
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
            topPages: breakdowns.pages,
            topReferrers: breakdowns.referrers,
            last24HoursVisitors: totals(from: last24).visitors
        )
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
