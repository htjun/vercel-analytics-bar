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
            id: "prj_personal_duplicate",
            name: "Team Dashboard"
        ),
        VercelProject(
            id: "prj_team_fixture_1",
            name: "Team Dashboard",
            teamID: "team_fixture",
            teamName: "Fixture Team"
        ),
        VercelProject(
            id: "prj_team_fixture_2",
            name: "Team Landing",
            teamID: "team_fixture",
            teamName: "Fixture Team"
        ),
        VercelProject(
            id: "prj_personal_fixture",
            name: "Zebra Site"
        ),
    ])
    #expect(projects.allSatisfy { $0.analyticsAvailability == .unknown })

    let requests = await transport.requests
    #expect(requests.count == 6)
    #expect(queryValue("teamId", in: requests[3]) == "team_fixture")
    #expect(queryValue("teamId", in: requests[5]) == "team_second")
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

private actor FixtureTransport: VercelHTTPTransport {
    private var responses: [String: [FixtureResponse]]
    private(set) var requests: [URLRequest] = []

    init(responses: [String: [FixtureResponse]]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let path = request.url?.path, var pathResponses = responses[path], !pathResponses.isEmpty else {
            throw FixtureTransportError.missingResponse
        }

        let response = pathResponses.removeFirst()
        responses[path] = pathResponses
        requests.append(request)

        guard let url = request.url, let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: response.headers
        ) else {
            throw FixtureTransportError.invalidResponse
        }

        return (response.body, httpResponse)
    }
}

private struct FixtureResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    static func fixture(named name: String) throws -> FixtureResponse {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureTransportError.missingFixture
        }
        return try FixtureResponse(statusCode: 200, headers: [:], body: Data(contentsOf: url))
    }

    static func response(
        statusCode: Int,
        headers: [String: String] = [:],
        body: String = "{}"
    ) -> FixtureResponse {
        FixtureResponse(statusCode: statusCode, headers: headers, body: Data(body.utf8))
    }
}

private enum FixtureTransportError: Error {
    case missingFixture
    case missingResponse
    case invalidResponse
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    guard let url = request.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == name }?
        .value
}

private func date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: value) else {
        throw FixtureTransportError.missingFixture
    }
    return date
}
