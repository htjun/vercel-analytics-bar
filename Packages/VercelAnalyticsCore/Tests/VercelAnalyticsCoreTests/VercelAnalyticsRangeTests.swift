import Foundation
import Testing
import VercelAnalyticsCore

struct AnalyticsRangeExpectation: Sendable {
    let range: VercelAnalyticsRange
    let now: String
    let expectedCountSince: String
    let expectedCountUntil: String
    let expectedAggregateSince: String
    let expectedAggregateUntil: String
    let expectedAggregate: String
}

@Test(arguments: [
    AnalyticsRangeExpectation(
        range: .last24Hours,
        now: "2026-08-02T00:17:30.000Z",
        expectedCountSince: "2026-08-01T01:00:00.000Z",
        expectedCountUntil: "2026-08-02T01:00:00.000Z",
        expectedAggregateSince: "2026-08-01T01:00:00.000Z",
        expectedAggregateUntil: "2026-08-02T00:59:59.999Z",
        expectedAggregate: "hour"
    ),
    AnalyticsRangeExpectation(
        range: .last24Hours,
        now: "2026-08-02T01:00:00.000Z",
        expectedCountSince: "2026-08-01T02:00:00.000Z",
        expectedCountUntil: "2026-08-02T02:00:00.000Z",
        expectedAggregateSince: "2026-08-01T02:00:00.000Z",
        expectedAggregateUntil: "2026-08-02T01:59:59.999Z",
        expectedAggregate: "hour"
    ),
    AnalyticsRangeExpectation(
        range: .last7Days,
        now: "2026-08-02T00:00:00.000Z",
        expectedCountSince: "2026-07-26T00:00:00.000Z",
        expectedCountUntil: "2026-08-02T00:00:00.000Z",
        expectedAggregateSince: "2026-07-26T00:00:00.000Z",
        expectedAggregateUntil: "2026-08-01T23:59:59.999Z",
        expectedAggregate: "day"
    ),
    AnalyticsRangeExpectation(
        range: .last30Days,
        now: "2026-08-02T00:00:00.000Z",
        expectedCountSince: "2026-07-03T00:00:00.000Z",
        expectedCountUntil: "2026-08-02T00:00:00.000Z",
        expectedAggregateSince: "2026-07-03T00:00:00.000Z",
        expectedAggregateUntil: "2026-08-01T23:59:59.999Z",
        expectedAggregate: "day"
    ),
])
func clientMapsAnalyticsRanges(expectation: AnalyticsRangeExpectation) async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v1/query/web-analytics/visits/count": [.fixture(named: "analytics-count")],
            "/v1/query/web-analytics/visits/aggregate": [.fixture(named: "analytics-aggregate")],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)
    let project = VercelProject(id: "prj_fixture", name: "Fixture")
    let now = try date(expectation.now)

    _ = try await client.fetchCount(for: project, range: expectation.range, now: now)
    _ = try await client.fetchSeries(for: project, range: expectation.range, now: now)

    let requests = await transport.requests
    #expect(queryValue("since", in: requests[0]) == expectation.expectedCountSince)
    #expect(queryValue("until", in: requests[0]) == expectation.expectedCountUntil)
    #expect(queryValue("since", in: requests[1]) == expectation.expectedAggregateSince)
    #expect(queryValue("until", in: requests[1]) == expectation.expectedAggregateUntil)
    #expect(queryValue("by", in: requests[1]) == expectation.expectedAggregate)
}

@Test(arguments: [
    (VercelAnalyticsRange.last24Hours, "2026-08-01T00:00:00.000Z", 25, 3600.0, 24),
    (VercelAnalyticsRange.last7Days, "2026-07-25T00:00:00.000Z", 9, 86400.0, 7),
    (VercelAnalyticsRange.last30Days, "2026-07-02T00:00:00.000Z", 32, 86400.0, 30),
])
func clientFiltersRoundedAggregateRowsToLogicalBucketCount(
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
            "/v1/query/web-analytics/visits/aggregate": [aggregateFixture(points: points)],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)
    let project = VercelProject(id: "prj_fixture", name: "Fixture")
    let now = try date("2026-08-02T00:17:30.000Z")

    let series = try await client.fetchSeries(for: project, range: range, now: now)

    #expect(series.points.count == expectedPointCount)
    #expect(series.points.first?.timestamp == start.addingTimeInterval(bucketDuration))
    #expect(series.points.last?.timestamp == start
        .addingTimeInterval(TimeInterval(expectedPointCount) * bucketDuration))
}

@Test func snapshotProviderLoadsVisitorsForOneProductionProject() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v1/query/web-analytics/visits/aggregate": [
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-pages", query: ["by": "requestPath"]),
            ],
        ]
    )
    let project = VercelProject(id: "prj_team_fixture_1", name: "Team Dashboard", teamID: "team_fixture")
    let now = try date("2026-08-02T00:00:00.000Z")
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: project,
        now: { now },
        transport: transport
    )

    let snapshot = try await provider.snapshot(for: .last24Hours)

    #expect(try snapshot == AnalyticsSnapshot(
        projectName: "Team Dashboard",
        range: .last24Hours,
        visitors: AnalyticsMetric(label: "Visitors", value: 22, previousValue: 0),
        pageViews: AnalyticsMetric(label: "Page Views", value: 39, previousValue: 0),
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
        last24HoursVisitors: 22,
        refreshedAt: now
    ))
    let requests = await transport.requests
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { queryValue("projectId", in: $0) == "prj_team_fixture_1" })
    #expect(requests.allSatisfy { queryValue("teamId", in: $0) == "team_fixture" })
    #expect(requests.allSatisfy { queryValue("filter", in: $0) == "environment eq 'production'" })
    #expect(requests.count(where: { queryValue("by", in: $0) == "hour" }) == 2)
    #expect(requests.count(where: { queryValue("by", in: $0) == "requestPath" }) == 1)
    let seriesRequests = requests.filter { queryValue("by", in: $0) == "hour" }
    #expect(Set(seriesRequests.map { "\(queryValue("since", in: $0)!)|\(queryValue("until", in: $0)!)" }) == Set([
        "2026-08-01T01:00:00.000Z|2026-08-02T00:59:59.999Z",
        "2026-07-31T01:00:00.000Z|2026-08-01T00:59:59.999Z",
    ]))
}

@Test func snapshotProviderUsesCompletedDayCountsAndAlignedLast24Series() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v1/query/web-analytics/visits/count": [
                .fixture(named: "analytics-count"),
                .fixture(named: "analytics-count"),
            ],
            "/v1/query/web-analytics/visits/aggregate": [
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-aggregate"),
                .fixture(named: "analytics-pages", query: ["by": "requestPath"]),
            ],
        ]
    )
    let project = VercelProject(
        id: "prj_team_fixture_1",
        name: "Team Dashboard",
        teamID: "team_fixture"
    )
    let now = try date("2026-08-02T00:00:00.000Z")
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: project,
        now: { now },
        transport: transport
    )

    let snapshot = try await provider.snapshot(for: .last7Days)
    let expectedSeries = try [
        VercelAnalyticsPoint(
            timestamp: date("2026-08-01T23:00:00.000Z"),
            visitors: 10,
            pageViews: 18
        ),
    ]

    #expect(snapshot.visitors == AnalyticsMetric(label: "Visitors", value: 165, previousValue: 165))
    #expect(snapshot.pageViews == AnalyticsMetric(label: "Page Views", value: 284, previousValue: 284))
    #expect(snapshot.series == expectedSeries)
    #expect(snapshot.topPages.count == 5)
    #expect(snapshot.last24HoursVisitors == 22)

    let requests = await transport.requests
    #expect(requests.count == 5)
    #expect(requests.count(where: { queryValue("by", in: $0) == "day" }) == 1)
    #expect(requests.count(where: { queryValue("by", in: $0) == "hour" }) == 1)
    #expect(requests.count(where: { queryValue("by", in: $0) == "requestPath" }) == 1)
    let countRequests = requests.filter { queryValue("by", in: $0) == nil }
    #expect(Set(countRequests.map { "\(queryValue("since", in: $0)!)|\(queryValue("until", in: $0)!)" }) == Set([
        "2026-07-26T00:00:00.000Z|2026-08-02T00:00:00.000Z",
        "2026-07-19T00:00:00.000Z|2026-07-26T00:00:00.000Z",
    ]))
}

@Test func snapshotProviderTreatsEmptyAggregateSeriesAsZero() async throws {
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
            "/v1/query/web-analytics/visits/aggregate": [
                emptyAggregate,
                emptyAggregate,
                .response(statusCode: 200, body: """
                {
                  "version": 1,
                  "query": {
                    "since": "2026-08-01T01:00:00.000Z",
                    "until": "2026-08-02T00:59:59.999Z"
                  },
                  "data": []
                }
                """),
            ],
        ]
    )
    let now = try date("2026-08-02T00:17:30.000Z")
    let provider = VercelAnalyticsSnapshotProvider(
        token: "fixture-token",
        project: VercelProject(id: "prj_fixture", name: "Fixture"),
        now: { now },
        transport: transport
    )

    let snapshot = try await provider.snapshot(for: .last24Hours)

    #expect(snapshot.visitors == AnalyticsMetric(label: "Visitors", value: 0, previousValue: 0))
    #expect(snapshot.pageViews == AnalyticsMetric(label: "Page Views", value: 0, previousValue: 0))
    #expect(snapshot.series.isEmpty)
    #expect(snapshot.topPages.isEmpty)
    #expect(snapshot.last24HoursVisitors == 0)
}
