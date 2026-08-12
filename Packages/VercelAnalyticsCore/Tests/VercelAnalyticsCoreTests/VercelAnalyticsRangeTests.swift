import Foundation
import Testing
@testable import VercelAnalyticsCore

struct AnalyticsRangeExpectation: Sendable {
    let range: VercelAnalyticsRange
    let now: String
    let expectedAggregateSince: String
    let expectedAggregateUntil: String
    let expectedAggregate: String
}

struct AnalyticsRangePlanExpectation: Sendable {
    let range: VercelAnalyticsRange
    let now: String
    let timeZoneIdentifier: String
    let expectedCurrentStart: String
    let expectedCurrentEnd: String
    let expectedPreviousStart: String
    let expectedPreviousEnd: String
    let expectedBucket: VercelAnalyticsBucket
}

@Test(arguments: [
    AnalyticsRangePlanExpectation(
        range: .last24Hours,
        now: "2026-08-11T10:30:00.000Z",
        timeZoneIdentifier: "Australia/Melbourne",
        expectedCurrentStart: "2026-08-10T11:00:00.000Z",
        expectedCurrentEnd: "2026-08-11T11:00:00.000Z",
        expectedPreviousStart: "2026-08-09T11:00:00.000Z",
        expectedPreviousEnd: "2026-08-10T11:00:00.000Z",
        expectedBucket: .hour
    ),
    AnalyticsRangePlanExpectation(
        range: .last7Days,
        now: "2026-08-11T10:30:00.000Z",
        timeZoneIdentifier: "Australia/Melbourne",
        expectedCurrentStart: "2026-08-04T10:00:00.000Z",
        expectedCurrentEnd: "2026-08-11T11:00:00.000Z",
        expectedPreviousStart: "2026-07-28T09:00:00.000Z",
        expectedPreviousEnd: "2026-08-04T10:00:00.000Z",
        expectedBucket: .day
    ),
    AnalyticsRangePlanExpectation(
        range: .last30Days,
        now: "2026-08-11T10:30:00.000Z",
        timeZoneIdentifier: "Australia/Melbourne",
        expectedCurrentStart: "2026-07-12T10:00:00.000Z",
        expectedCurrentEnd: "2026-08-11T11:00:00.000Z",
        expectedPreviousStart: "2026-06-12T09:00:00.000Z",
        expectedPreviousEnd: "2026-07-12T10:00:00.000Z",
        expectedBucket: .day
    ),
])
func analyticsRangeOwnsAlignedCurrentAndPreviousWindows(expectation: AnalyticsRangePlanExpectation) throws {
    let timeZone = try #require(TimeZone(identifier: expectation.timeZoneIdentifier))
    let plan = try expectation.range.plan(at: date(expectation.now), timeZone: timeZone)
    let expectedCurrentStart = try date(expectation.expectedCurrentStart)
    let expectedCurrentEnd = try date(expectation.expectedCurrentEnd)
    let expectedPreviousStart = try date(expectation.expectedPreviousStart)
    let expectedPreviousEnd = try date(expectation.expectedPreviousEnd)

    #expect(plan.currentWindow.start == expectedCurrentStart)
    #expect(plan.currentWindow.endExclusive == expectedCurrentEnd)
    #expect(plan.previousWindow.start == expectedPreviousStart)
    #expect(plan.previousWindow.endExclusive == expectedPreviousEnd)
    #expect(plan.bucket == expectation.expectedBucket)
    #expect(plan.currentWindow.currentOverviewWindow.since == expectedCurrentStart)
    #expect(plan.currentWindow.currentOverviewWindow.until == expectedCurrentEnd.addingTimeInterval(-0.001))
    #expect(plan.previousWindow.previousOverviewWindow.since == expectedPreviousStart.addingTimeInterval(0.001))
    #expect(plan.previousWindow.previousOverviewWindow.until == expectedPreviousEnd)
}

@Test(arguments: [
    AnalyticsRangeExpectation(
        range: .last24Hours,
        now: "2026-08-02T00:17:30.000Z",
        expectedAggregateSince: "2026-08-01T01:00:00.000Z",
        expectedAggregateUntil: "2026-08-02T00:59:59.999Z",
        expectedAggregate: "hour"
    ),
    AnalyticsRangeExpectation(
        range: .last24Hours,
        now: "2026-08-02T01:00:00.000Z",
        expectedAggregateSince: "2026-08-01T02:00:00.000Z",
        expectedAggregateUntil: "2026-08-02T01:59:59.999Z",
        expectedAggregate: "hour"
    ),
    AnalyticsRangeExpectation(
        range: .last7Days,
        now: "2026-08-02T00:00:00.000Z",
        expectedAggregateSince: "2026-07-26T00:00:00.000Z",
        expectedAggregateUntil: "2026-08-02T00:59:59.999Z",
        expectedAggregate: "day"
    ),
    AnalyticsRangeExpectation(
        range: .last30Days,
        now: "2026-08-02T00:00:00.000Z",
        expectedAggregateSince: "2026-07-03T00:00:00.000Z",
        expectedAggregateUntil: "2026-08-02T00:59:59.999Z",
        expectedAggregate: "day"
    ),
])
func snapshotProviderMapsAnalyticsRanges(expectation: AnalyticsRangeExpectation) async throws {
    let overviewResponseCount = expectation.range == .last24Hours ? 2 : 3
    let transport = try FixtureTransport(
        responses: [
            "/web-analytics/v2/overview": (0 ..< overviewResponseCount).map { _ in
                .response(statusCode: 200, body: #"{"devices":1,"total":2}"#)
            },
            "/v1/query/web-analytics/visits/aggregate": [
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-pages", query: ["by": "requestPath"]),
                .fixture(named: "analytics-referrers", query: ["by": "referrerHostname"]),
            ],
        ]
    )
    let project = VercelProject(id: "prj_fixture", name: "Fixture")
    let now = try date(expectation.now)
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: project,
        now: { now },
        timeZone: { utc },
        transport: transport
    )

    _ = try await provider.snapshot(for: expectation.range)

    let requests = await transport.requests
    let currentOverviewRequest = try #require(requests.first { request in
        request.url?.path == "/web-analytics/v2/overview"
            && queryValue("from", in: request) == expectation.expectedAggregateSince
    })
    #expect(queryValue("to", in: currentOverviewRequest) == expectation.expectedAggregateUntil)
    let seriesRequest = try #require(requests.first { request in
        queryValue("by", in: request) == expectation.expectedAggregate
    })
    #expect(queryValue("since", in: seriesRequest) == expectation.expectedAggregateSince)
    #expect(queryValue("until", in: seriesRequest) == expectation.expectedAggregateUntil)
}

@Test(arguments: [
    (VercelAnalyticsRange.last24Hours, "2026-08-01T00:00:00.000Z", 25, 3600.0, 24),
    (VercelAnalyticsRange.last7Days, "2026-07-25T00:00:00.000Z", 9, 86400.0, 8),
    (VercelAnalyticsRange.last30Days, "2026-07-02T00:00:00.000Z", 32, 86400.0, 31),
])
func snapshotProviderFiltersRoundedAggregateRowsToLogicalBucketCount(
    range: VercelAnalyticsRange,
    dataStart: String,
    sourcePointCount: Int,
    bucketDuration: TimeInterval,
    expectedPointCount: Int
) async throws {
    let start = try date(dataStart)
    let points = (0 ..< sourcePointCount).map { index in
        AggregateFixturePoint(
            timestamp: start.addingTimeInterval(TimeInterval(index) * bucketDuration),
            visitors: 1,
            pageViews: 1
        )
    }
    let transport = try FixtureTransport(
        responses: [
            "/web-analytics/v2/overview": (0 ..< (range == .last24Hours ? 2 : 3)).map { _ in
                .response(statusCode: 200, body: #"{"devices":1,"total":2}"#)
            },
            "/v1/query/web-analytics/visits/aggregate": [
                aggregateFixture(points: points),
                .fixture(named: "analytics-pages", query: ["by": "requestPath"]),
                .fixture(named: "analytics-referrers", query: ["by": "referrerHostname"]),
            ],
        ]
    )
    let project = VercelProject(id: "prj_fixture", name: "Fixture")
    let now = try date("2026-08-02T00:17:30.000Z")
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: project,
        now: { now },
        timeZone: { utc },
        transport: transport
    )

    let series = try await provider.snapshot(for: range).series

    #expect(series.count == expectedPointCount)
    #expect(series.first?.timestamp == start.addingTimeInterval(bucketDuration))
    #expect(series.last?.timestamp == start
        .addingTimeInterval(TimeInterval(expectedPointCount) * bucketDuration))
}

@Test func snapshotProviderLoadsVisitorsForOneProductionProject() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/web-analytics/v2/overview": [
                overviewResponse(devices: 14, total: 46, from: "2026-08-01T01:00:00.000Z"),
                overviewResponse(devices: 15, total: 49, from: "2026-07-31T01:00:00.001Z"),
            ],
            "/v1/query/web-analytics/visits/aggregate": [
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-pages", query: ["by": "requestPath"]),
                .fixture(named: "analytics-referrers", query: ["by": "referrerHostname"]),
            ],
        ]
    )
    let project = VercelProject(id: "prj_team_fixture_1", name: "Team Dashboard", teamID: "team_fixture")
    let now = try date("2026-08-02T00:00:00.000Z")
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: project,
        now: { now },
        timeZone: { TimeZone(secondsFromGMT: 0)! },
        transport: transport
    )

    let snapshot = try await provider.snapshot(for: .last24Hours)

    #expect(try snapshot == expectedLast24Snapshot(refreshedAt: now))
    let requests = await transport.requests
    #expect(requests.count == 5)
    #expect(requests.allSatisfy { queryValue("teamId", in: $0) == "team_fixture" })
    #expect(requests.count(where: { queryValue("by", in: $0) == "hour" }) == 1)
    #expect(requests.count(where: { queryValue("by", in: $0) == "requestPath" }) == 1)
    #expect(requests.count(where: { queryValue("by", in: $0) == "referrerHostname" }) == 1)
    let breakdownRequests = requests.filter { request in
        ["requestPath", "referrerHostname"].contains(queryValue("by", in: request))
    }
    #expect(breakdownRequests.allSatisfy { queryValue("limit", in: $0) == "10" })
    let overviewRequests = requests.filter { $0.url?.path == "/web-analytics/v2/overview" }
    #expect(Set(overviewRequests.map { "\(queryValue("from", in: $0)!)|\(queryValue("to", in: $0)!)" }) == Set([
        "2026-08-01T01:00:00.000Z|2026-08-02T00:59:59.999Z",
        "2026-07-31T01:00:00.001Z|2026-08-01T01:00:00.000Z",
    ]))
    #expect(overviewRequests.allSatisfy { queryValue("projectId", in: $0) == "Team Dashboard" })
    #expect(overviewRequests.allSatisfy { queryValue("environment", in: $0) == "production" })
    #expect(overviewRequests.allSatisfy { queryValue("filter", in: $0) == "{}" })
    #expect(overviewRequests.allSatisfy { queryValue("tz", in: $0) == "GMT" })
    let publicRequests = requests.filter { $0.url?.path != "/web-analytics/v2/overview" }
    #expect(publicRequests.allSatisfy { queryValue("projectId", in: $0) == "prj_team_fixture_1" })
    #expect(publicRequests.allSatisfy { queryValue("filter", in: $0) == "environment eq 'production'" })
}

@Test func snapshotProviderUsesDashboardOverviewTotalsAndLast24Visitors() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/web-analytics/v2/overview": [
                overviewResponse(devices: 136, total: 254, from: "2026-07-26T00:00:00.000Z"),
                overviewResponse(devices: 164, total: 265, from: "2026-07-18T23:00:00.001Z"),
                overviewResponse(devices: 14, total: 46, from: "2026-08-01T01:00:00.000Z"),
            ],
            "/v1/query/web-analytics/visits/aggregate": [
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-pages", query: ["by": "requestPath"]),
                .fixture(named: "analytics-referrers", query: ["by": "referrerHostname"]),
            ],
        ]
    )
    let project = VercelProject(id: "prj_team_fixture_1", name: "Team Dashboard", teamID: "team_fixture")
    let now = try date("2026-08-02T00:00:00.000Z")
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: project,
        now: { now },
        timeZone: { TimeZone(secondsFromGMT: 0)! },
        transport: transport
    )

    let snapshot = try await provider.snapshot(for: .last7Days)
    let expectedSeries = try expectedDashboardRangeSeries()

    #expect(snapshot.visitors == AnalyticsMetric(label: "Visitors", value: 136, previousValue: 164))
    #expect(snapshot.pageViews == AnalyticsMetric(label: "Page Views", value: 254, previousValue: 265))
    #expect(snapshot.series == expectedSeries)
    #expect(snapshot.topPages.count == 5)
    #expect(snapshot.topReferrers.count == 5)
    #expect(snapshot.last24HoursVisitors == 14)

    let requests = await transport.requests
    #expect(requests.count == 6)
    #expect(requests.count(where: { queryValue("by", in: $0) == "day" }) == 1)
    #expect(requests.count(where: { $0.url?.path == "/web-analytics/v2/overview" }) == 3)
    #expect(requests.count(where: { queryValue("by", in: $0) == "requestPath" }) == 1)
    #expect(requests.count(where: { queryValue("by", in: $0) == "referrerHostname" }) == 1)
    let overviewRequests = requests.filter { $0.url?.path == "/web-analytics/v2/overview" }
    #expect(Set(overviewRequests.map { "\(queryValue("from", in: $0)!)|\(queryValue("to", in: $0)!)" }) == Set([
        "2026-07-26T00:00:00.000Z|2026-08-02T00:59:59.999Z",
        "2026-07-18T23:00:00.001Z|2026-07-26T00:00:00.000Z",
        "2026-08-01T01:00:00.000Z|2026-08-02T00:59:59.999Z",
    ]))
}

@Test func snapshotProviderKeepsDashboardTotalsWhenAggregateSeriesIsEmpty() async throws {
    let emptyAggregate = FixtureResponse.response(
        statusCode: 200,
        body: """
        {
          "version": 1,
          "query": {
            "since": "2026-08-01T01:00:00.000Z",
            "until": "2026-08-02T00:59:59.999Z"
          },
          "data": []
        }
        """
    )
    let transport = FixtureTransport(
        responses: [
            "/web-analytics/v2/overview": [
                overviewResponse(devices: 14, total: 46, from: "2026-08-01T01:00:00.000Z"),
                overviewResponse(devices: 15, total: 49, from: "2026-07-31T01:00:00.001Z"),
            ],
            "/v1/query/web-analytics/visits/aggregate": [
                emptyAggregate,
                emptyAggregate,
                emptyAggregate,
            ],
        ]
    )
    let now = try date("2026-08-02T00:17:30.000Z")
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: VercelProject(id: "prj_fixture", name: "Fixture"),
        now: { now },
        timeZone: { TimeZone(secondsFromGMT: 0)! },
        transport: transport
    )

    let snapshot = try await provider.snapshot(for: .last24Hours)

    #expect(snapshot.visitors == AnalyticsMetric(label: "Visitors", value: 14, previousValue: 15))
    #expect(snapshot.pageViews == AnalyticsMetric(label: "Page Views", value: 46, previousValue: 49))
    #expect(snapshot.series.isEmpty)
    #expect(snapshot.topPages.isEmpty)
    #expect(snapshot.topReferrers.isEmpty)
    #expect(snapshot.last24HoursVisitors == 14)
    let requests = await transport.requests
    #expect(requests.allSatisfy { queryValue("teamId", in: $0) == nil })
}

private func expectedLast24Snapshot(refreshedAt: Date) throws -> AnalyticsSnapshot {
    try AnalyticsSnapshot(
        projectName: "Team Dashboard",
        range: .last24Hours,
        visitors: AnalyticsMetric(label: "Visitors", value: 14, previousValue: 15),
        pageViews: AnalyticsMetric(label: "Page Views", value: 46, previousValue: 49),
        series: [
            VercelAnalyticsPoint(
                timestamp: date("2026-08-01T23:00:00.000Z"),
                visitors: 10,
                pageViews: 18
            ),
            VercelAnalyticsPoint(
                timestamp: date("2026-08-02T00:00:00.000Z"),
                visitors: 12,
                pageViews: 21
            ),
        ],
        topPages: [
            VercelAnalyticsBreakdown(label: "/products", visitors: 820, pageViews: 1280),
            VercelAnalyticsBreakdown(label: "/pricing", visitors: 615, pageViews: 940),
            VercelAnalyticsBreakdown(label: "/docs", visitors: 410, pageViews: 690),
            VercelAnalyticsBreakdown(label: "/blog", visitors: 330, pageViews: 520),
            VercelAnalyticsBreakdown(label: "/about", visitors: 180, pageViews: 240),
        ],
        topReferrers: [
            VercelAnalyticsBreakdown(label: "google.com", visitors: 510, pageViews: 640),
            VercelAnalyticsBreakdown(label: "news.ycombinator.com", visitors: 205, pageViews: 260),
            VercelAnalyticsBreakdown(label: "github.com", visitors: 160, pageViews: 195),
            VercelAnalyticsBreakdown(label: "linkedin.com", visitors: 95, pageViews: 120),
            VercelAnalyticsBreakdown(label: "example.com", visitors: 40, pageViews: 55),
        ],
        last24HoursVisitors: 14,
        refreshedAt: refreshedAt
    )
}

private func overviewResponse(devices: Int, total: Int, from: String) -> FixtureResponse {
    .response(
        statusCode: 200,
        body: #"{"devices":\#(devices),"total":\#(total)}"#,
        query: ["from": from]
    )
}

private func expectedDashboardRangeSeries() throws -> [VercelAnalyticsPoint] {
    try [
        VercelAnalyticsPoint(
            timestamp: date("2026-08-01T23:00:00.000Z"),
            visitors: 10,
            pageViews: 18
        ),
        VercelAnalyticsPoint(
            timestamp: date("2026-08-02T00:00:00.000Z"),
            visitors: 12,
            pageViews: 21
        ),
    ]
}
