import Foundation
import VercelAnalyticsCore

struct ProjectSwitchSnapshotFixture {
    let alpha: AnalyticsSnapshot
    let refreshedAlpha: AnalyticsSnapshot
    let beta: AnalyticsSnapshot
}

func makeProjectSwitchSnapshotFixture() -> ProjectSwitchSnapshotFixture {
    let initialRefreshDate = Date(timeIntervalSince1970: 1_785_549_600)
    return ProjectSwitchSnapshotFixture(
        alpha: makeAnalyticsSnapshot(
            projectName: "Alpha",
            visitors: 100,
            pageViews: 200,
            last24HoursVisitors: 11,
            refreshedAt: initialRefreshDate,
            range: .last24Hours
        ),
        refreshedAlpha: makeAnalyticsSnapshot(
            projectName: "Alpha",
            visitors: 101,
            pageViews: 202,
            last24HoursVisitors: 12,
            refreshedAt: initialRefreshDate.addingTimeInterval(60),
            range: .last24Hours
        ),
        beta: makeAnalyticsSnapshot(
            projectName: "Beta",
            visitors: 300,
            pageViews: 500,
            last24HoursVisitors: 22,
            refreshedAt: initialRefreshDate,
            range: .last24Hours
        )
    )
}

func makeAnalyticsSnapshot(
    projectName: String,
    visitors: Int,
    pageViews: Int,
    last24HoursVisitors: Int,
    refreshedAt: Date,
    range: VercelAnalyticsRange = .last7Days,
    topPages: [VercelAnalyticsBreakdown] = []
) -> AnalyticsSnapshot {
    AnalyticsSnapshot(
        projectName: projectName,
        range: range,
        visitors: AnalyticsMetric(label: "Visitors", value: visitors, previousValue: visitors * 9 / 10),
        pageViews: AnalyticsMetric(label: "Page Views", value: pageViews, previousValue: pageViews * 9 / 10),
        series: [],
        topPages: topPages,
        last24HoursVisitors: last24HoursVisitors,
        refreshedAt: refreshedAt
    )
}
