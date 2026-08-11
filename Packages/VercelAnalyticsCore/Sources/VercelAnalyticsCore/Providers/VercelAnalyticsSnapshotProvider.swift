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
    private let timeZoneProvider: @Sendable () -> TimeZone

    public init(
        token: String,
        project: VercelProject,
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        baseURL: URL = VercelAPIClient.defaultBaseURL,
        transport: any VercelHTTPTransport = URLSessionVercelHTTPTransport()
    ) {
        client = VercelAPIClient(token: token, baseURL: baseURL, transport: transport)
        self.project = project
        self.now = now
        timeZoneProvider = timeZone
    }

    public func snapshot(for range: VercelAnalyticsRange) async throws -> AnalyticsSnapshot {
        let refreshedAt = now()
        let currentTimeZone = timeZoneProvider()
        let plan = range.plan(at: refreshedAt, timeZone: currentTimeZone)
        async let currentOverview = client.fetchOverview(
            for: project,
            window: plan.currentWindow.currentOverviewWindow,
            timeZone: currentTimeZone
        )
        async let previousOverview = client.fetchOverview(
            for: project,
            window: plan.previousWindow.previousOverviewWindow,
            timeZone: currentTimeZone
        )
        async let currentSeries = client.fetchSeries(
            for: project,
            window: plan.currentWindow,
            bucket: plan.bucket
        )
        async let last24HoursOverview: VercelAnalyticsCount? = if range == .last24Hours {
            nil
        } else {
            try await fetchLast24HoursOverview(at: refreshedAt, timeZone: currentTimeZone)
        }
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

        let (current, previous, series, last24, pages, referrers) = try await (
            currentOverview,
            previousOverview,
            currentSeries,
            last24HoursOverview,
            topPages,
            topReferrers
        )
        let data = makeSnapshotData(
            current: current,
            previous: previous,
            series: series,
            last24Hours: last24,
            breakdowns: (pages: pages, referrers: referrers)
        )

        return makeSnapshot(range: range, data: data, refreshedAt: refreshedAt)
    }

    private func makeSnapshotData(
        current: VercelAnalyticsCount,
        previous: VercelAnalyticsCount,
        series: VercelAnalyticsSeries,
        last24Hours: VercelAnalyticsCount?,
        breakdowns: (pages: [VercelAnalyticsBreakdown], referrers: [VercelAnalyticsBreakdown])
    ) -> SnapshotData {
        SnapshotData(
            visitors: AnalyticsMetric(
                label: "Visitors",
                value: current.visitors,
                previousValue: previous.visitors
            ),
            pageViews: AnalyticsMetric(
                label: "Page Views",
                value: current.pageViews,
                previousValue: previous.pageViews
            ),
            series: series.points,
            topPages: breakdowns.pages,
            topReferrers: breakdowns.referrers,
            last24HoursVisitors: last24Hours?.visitors ?? current.visitors
        )
    }

    private func fetchLast24HoursOverview(
        at date: Date,
        timeZone: TimeZone
    ) async throws -> VercelAnalyticsCount {
        let window = VercelAnalyticsRange.last24Hours
            .plan(at: date, timeZone: timeZone)
            .currentWindow
            .currentOverviewWindow
        return try await client.fetchOverview(
            for: project,
            window: window,
            timeZone: timeZone
        )
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
