import Foundation
import Testing
import VercelAnalyticsCore

@Test func clientListsTeamsAcrossPages() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v2/teams": [
                .fixture(named: "teams-page-1"),
                .fixture(named: "teams-page-2"),
            ],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    let teams = try await client.listTeams()

    #expect(teams == [
        VercelTeam(id: "team_fixture", name: "Fixture Team", slug: "fixture-team"),
        VercelTeam(id: "team_second", name: "Second Team"),
    ])

    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(queryValue("limit", in: requests[0]) == "100")
    #expect(queryValue("until", in: requests[1]) == "123")
}

@Test func clientListsPersonalAndTeamProjectsWithScopeAndPagination() async throws {
    let personalTransport = try FixtureTransport(
        responses: ["/v9/projects": [.fixture(named: "projects-personal")]]
    )
    let personalClient = VercelAPIClient(token: "fixture-token", transport: personalTransport)
    let personalProjects = try await personalClient.listProjects()

    #expect(personalProjects == [
        VercelProject(id: "prj_personal_fixture", name: "Personal Site"),
    ])
    let personalRequests = await personalTransport.requests
    #expect(queryValue("teamId", in: personalRequests[0]) == nil)

    let teamTransport = try FixtureTransport(
        responses: [
            "/v9/projects": [
                .fixture(named: "projects-team-page-1"),
                .fixture(named: "projects-team-page-2"),
            ],
        ]
    )
    let teamClient = VercelAPIClient(token: "fixture-token", transport: teamTransport)
    let teamProjects = try await teamClient.listProjects(teamID: "team_fixture")

    #expect(teamProjects == [
        VercelProject(
            id: "prj_team_fixture_1",
            name: "Team Dashboard",
            teamID: "team_fixture"
        ),
        VercelProject(
            id: "prj_team_fixture_2",
            name: "Team Landing",
            teamID: "team_fixture"
        ),
    ])
    let teamRequests = await teamTransport.requests
    #expect(queryValue("teamId", in: teamRequests[0]) == "team_fixture")
    #expect(queryValue("until", in: teamRequests[1]) == "cursor-two")
}

@Test func clientListsAllAccessibleProjectsWithTeamMetadataAndSorting() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v2/user": [.fixture(named: "authenticated-user")],
            "/v2/teams": [
                .fixture(named: "teams-page-1"),
                .fixture(named: "teams-page-2"),
            ],
            "/v9/projects": [
                .fixture(named: "projects-discovery-personal"),
                .fixture(named: "projects-team-page-1"),
                .fixture(named: "projects-team-page-2"),
                .fixture(named: "projects-team-second-empty"),
            ],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    let projects = try await client.listAccessibleProjects()

    #expect(projects == [
        VercelProject(
            id: "prj_team_fixture_1",
            name: "Team Dashboard",
            teamID: "team_fixture",
            teamName: "Fixture Team",
            scopeSlug: "fixture-team"
        ),
        VercelProject(
            id: "prj_team_fixture_2",
            name: "Team Landing",
            teamID: "team_fixture",
            teamName: "Fixture Team",
            scopeSlug: "fixture-team"
        ),
        VercelProject(
            id: "prj_personal_fixture",
            name: "Zebra Site",
            scopeSlug: "fixture-user"
        ),
    ])
    #expect(projects.allSatisfy { $0.analyticsAvailability == .unknown })

    let requests = await transport.requests
    #expect(requests.count == 7)
    #expect(queryValue("teamId", in: requests[4]) == "team_fixture")
    #expect(queryValue("teamId", in: requests[6]) == "team_second")
}

@Test(arguments: [
    (VercelAnalyticsRange.last24Hours, "24h"),
    (VercelAnalyticsRange.last7Days, "7d"),
    (VercelAnalyticsRange.last30Days, "30d"),
])
func projectBuildsAnalyticsDashboardURL(range: VercelAnalyticsRange, period: String) throws {
    let project = VercelProject(
        id: "prj_fixture",
        name: "fixture-project",
        scopeSlug: "fixture-team"
    )

    let url = try #require(project.analyticsDashboardURL(for: range))
    #expect(url.absoluteString == "https://vercel.com/fixture-team/fixture-project/analytics?period=\(period)")
}

@Test func projectWithoutScopeDoesNotBuildAnalyticsDashboardURL() {
    let project = VercelProject(id: "prj_fixture", name: "fixture-project")

    #expect(project.analyticsDashboardURL(for: .last24Hours) == nil)
}

@Test func clientMapsCountAndSeriesAndSendsProductionQuery() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v1/query/web-analytics/visits/count": [.fixture(named: "analytics-count")],
            "/v1/query/web-analytics/visits/aggregate": [.fixture(named: "analytics-aggregate")],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)
    let project = VercelProject(id: "prj_team_fixture_1", name: "Team Dashboard", teamID: "team_fixture")
    let now = try date("2026-08-02T00:00:00.000Z")

    let count = try await client.fetchCount(for: project, range: .last24Hours, now: now)
    let series = try await client.fetchSeries(for: project, range: .last24Hours, now: now)

    #expect(count.visitors == 165)
    #expect(count.pageViews == 284)
    #expect(try count.window == VercelAnalyticsWindow(
        since: date("2026-08-01T00:00:00.000Z"),
        until: date("2026-08-02T00:00:00.000Z")
    ))
    #expect(try series.points == [
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
    ])

    let requests = await transport.requests
    #expect(queryValue("projectId", in: requests[0]) == "prj_team_fixture_1")
    #expect(queryValue("teamId", in: requests[0]) == "team_fixture")
    #expect(queryValue("filter", in: requests[0]) == "environment eq 'production'")
    #expect(queryValue("by", in: requests[0]) == nil)
    #expect(queryValue("by", in: requests[1]) == "hour")
}

@Test(arguments: [
    (VercelAnalyticsRange.last24Hours, "2026-08-01T00:00:00.000Z", "hour"),
    (VercelAnalyticsRange.last7Days, "2026-07-26T00:00:00.000Z", "day"),
    (VercelAnalyticsRange.last30Days, "2026-07-03T00:00:00.000Z", "day"),
])
func clientMapsAnalyticsRanges(
    range: VercelAnalyticsRange,
    expectedSince: String,
    expectedAggregate: String
) async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v1/query/web-analytics/visits/count": [.fixture(named: "analytics-count")],
            "/v1/query/web-analytics/visits/aggregate": [.fixture(named: "analytics-aggregate")],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)
    let project = VercelProject(id: "prj_fixture", name: "Fixture")
    let now = try date("2026-08-02T00:00:00.000Z")

    _ = try await client.fetchCount(for: project, range: range, now: now)
    _ = try await client.fetchSeries(for: project, range: range, now: now)

    let requests = await transport.requests
    #expect(queryValue("since", in: requests[0]) == expectedSince)
    #expect(queryValue("until", in: requests[0]) == "2026-08-02T00:00:00.000Z")
    #expect(queryValue("by", in: requests[1]) == expectedAggregate)
}

@Test func snapshotProviderLoadsVisitorsForOneProductionProject() async throws {
    let transport = try FixtureTransport(
        responses: [
            "/v1/query/web-analytics/visits/count": [
                .fixture(named: "analytics-count"),
                .fixture(named: "analytics-count"),
            ],
            "/v1/query/web-analytics/visits/aggregate": [.fixture(named: "analytics-aggregate")],
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

    let snapshot = try await provider.snapshot(for: .last24Hours)

    #expect(try snapshot == AnalyticsSnapshot(
        projectName: "Team Dashboard",
        range: .last24Hours,
        visitors: AnalyticsMetric(label: "Visitors", value: 165, previousValue: 165),
        pageViews: AnalyticsMetric(label: "Page Views", value: 284, previousValue: 284),
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
        last24HoursVisitors: 165,
        refreshedAt: now
    ))
    let requests = await transport.requests
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { queryValue("projectId", in: $0) == "prj_team_fixture_1" })
    #expect(requests.allSatisfy { queryValue("teamId", in: $0) == "team_fixture" })
    #expect(requests.allSatisfy { queryValue("filter", in: $0) == "environment eq 'production'" })
}

@Test func clientMapsAuthenticationAndRedactsResponseBody() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/teams": [.response(statusCode: 403, body: "server-secret-response")],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    do {
        try await client.validateToken()
        Issue.record("Expected authentication failure")
    } catch let error as VercelAPIError {
        #expect(error == .authentication(status: 403))
        #expect(String(describing: error).contains("server-secret-response") == false)
        #expect(String(describing: error).contains("fixture-token") == false)
    }
}

@Test func clientMapsPermissionFailure() async throws {
    let permissionTransport = FixtureTransport(
        responses: [
            "/v9/projects": [.response(statusCode: 403, body: "private-response")],
        ]
    )
    do {
        _ = try await VercelAPIClient(token: "fixture-token", transport: permissionTransport).listProjects()
        Issue.record("Expected permission failure")
    } catch let error as VercelAPIError {
        #expect(error == .permissionDenied(status: 403))
    }
}

@Test func clientMapsRateLimitFailure() async throws {
    let rateLimitTransport = FixtureTransport(
        responses: [
            "/v2/teams": [
                .response(
                    statusCode: 429,
                    headers: [
                        "X-RateLimit-Limit": "100",
                        "X-RateLimit-Remaining": "0",
                        "X-RateLimit-Reset": "1785638400",
                        "Retry-After": "30",
                        "X-Vercel-Id": "fixture-request-id",
                    ],
                    body: "rate-limit-response"
                ),
            ],
        ]
    )
    do {
        try await VercelAPIClient(token: "fixture-token", transport: rateLimitTransport).validateToken()
        Issue.record("Expected rate-limit failure")
    } catch let error as VercelAPIError {
        guard case let .rateLimited(metadata) = error else {
            Issue.record("Expected a typed rate-limit error")
            return
        }
        #expect(metadata.limit == 100)
        #expect(metadata.remaining == 0)
        #expect(metadata.retryAfter == 30)
        #expect(metadata.requestID == "fixture-request-id")
    }
}

@Test func clientMapsTransientFailure() async throws {
    let transientTransport = FixtureTransport(
        responses: [
            "/v2/teams": [.response(statusCode: 503, headers: ["X-Vercel-Id": "fixture-request-id"])],
        ]
    )
    do {
        try await VercelAPIClient(token: "fixture-token", transport: transientTransport).validateToken()
        Issue.record("Expected transient failure")
    } catch let error as VercelAPIError {
        #expect(error == .transient(status: 503, requestID: "fixture-request-id"))
    }
}

@Test func clientMapsMalformedSuccessfulResponseWithoutIncludingBody() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/teams": [.response(statusCode: 200, body: "malformed-secret-response")],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    do {
        try await client.validateToken()
        Issue.record("Expected malformed-response failure")
    } catch let error as VercelAPIError {
        #expect(error == .malformedResponse(endpoint: "/v2/teams"))
        #expect(String(describing: error).contains("malformed-secret-response") == false)
    }
}
