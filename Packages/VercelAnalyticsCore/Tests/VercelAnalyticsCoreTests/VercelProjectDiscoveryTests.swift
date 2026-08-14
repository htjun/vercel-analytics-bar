import Foundation
import Testing
import VercelAnalyticsCore

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

    let discovery = try await client.discoverAccount()
    let projects = discovery.projects

    #expect(discovery.profile == VercelAccountProfile(
        id: "user_fixture",
        name: "Fixture User",
        username: "fixture-user",
        avatarURL: URL(string: "https://api.vercel.com/www/avatar/fixture-avatar")
    ))

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
    let requests = await transport.requests
    expectDiscoveryRequests(requests)
}

@Test func accountProfileFallsBackFromNameToUsername() {
    #expect(VercelAccountProfile(name: "  ", username: "fixture-user").displayName == "fixture-user")
    #expect(VercelAccountProfile().displayName == "Vercel account")
}

@Test func clientDecodesProjectUpdatedAtMillisecondsAndSortsNewestFirst() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [.response(statusCode: 200, body: #"{"user":{"id":"user_fixture"}}"#)],
            "/v2/teams": [.response(statusCode: 200, body: emptyTeamsPage)],
            "/v9/projects": [.response(statusCode: 200, body: projectsWithUpdatedAtPage)],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    let projects = try await client.listAccessibleProjects()

    #expect(projects.map(\.id) == ["newest", "same-a", "same-b", "older", "missing"])
    #expect(projects[0].updatedAt == Date(timeIntervalSince1970: 1_786_000_000))
    #expect(projects[4].updatedAt == nil)
}

@Test func projectSortingUsesDeterministicTiesAndPlacesMissingDatesLast() {
    let newest = Date(timeIntervalSince1970: 300)
    let tied = Date(timeIntervalSince1970: 200)
    let projects = [
        VercelProject(id: "missing", name: "Aardvark"),
        VercelProject(id: "older", name: "Alpha", updatedAt: Date(timeIntervalSince1970: 100)),
        VercelProject(id: "z-id", name: "beta", updatedAt: tied, teamName: "Zulu"),
        VercelProject(id: "b-id", name: "Alpha", updatedAt: tied, teamName: "Bravo"),
        VercelProject(id: "a-id", name: "alpha", updatedAt: tied, teamName: "Bravo"),
        VercelProject(id: "newest", name: "Zebra", updatedAt: newest),
    ]

    #expect(VercelProject.sorted(projects).map(\.id) == [
        "newest",
        "a-id",
        "b-id",
        "z-id",
        "older",
        "missing",
    ])
}

@Test func clientContinuesWithTeamProjectsWhenPersonalScopeIsUnavailable() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [.response(statusCode: 404)],
            "/v2/teams": [.response(statusCode: 200, body: singleTeamPage)],
            "/v9/projects": [
                .response(
                    statusCode: 200,
                    body: singleTeamProjectPage,
                    query: ["teamId": "team_fixture"]
                ),
            ],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    let projects = try await client.listAccessibleProjects()

    #expect(projects == [
        VercelProject(
            id: "prj_team_fixture",
            name: "Team Project",
            teamID: "team_fixture",
            teamName: "Fixture Team",
            scopeSlug: "fixture-team"
        ),
    ])
    let projectRequests = await transport.requests.filter { $0.url?.path == "/v9/projects" }
    #expect(projectRequests.count == 1)
    #expect(projectRequests.allSatisfy { queryValue("teamId", in: $0) == "team_fixture" })
}

@Test func clientPropagatesPersonalScopeFailuresOtherThanNotFound() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [
                .response(
                    statusCode: 503,
                    headers: ["X-Vercel-Id": "fixture-request-id"]
                ),
            ],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    do {
        _ = try await client.listAccessibleProjects()
        Issue.record("Expected personal-scope discovery failure")
    } catch let error as VercelAPIError {
        #expect(error == .transient(status: 503, requestID: "fixture-request-id"))
    }

    let requests = await transport.requests
    #expect(requests.count == 1)
}

@Test func clientIncludesPersonalProjectsWhenUsernameIsMissing() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [.response(statusCode: 200, body: #"{"user":{"username":null}}"#)],
            "/v2/teams": [.response(statusCode: 200, body: emptyTeamsPage)],
            "/v9/projects": [.response(statusCode: 200, body: personalProjectPage)],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    let projects = try await client.listAccessibleProjects()

    #expect(projects == [VercelProject(id: "prj_personal_fixture", name: "Personal Project")])
    let projectRequest = try #require(await transport.requests.first { $0.url?.path == "/v9/projects" })
    #expect(queryValue("teamId", in: projectRequest) == nil)
}

@Test func clientFailsDiscoveryWhenAnAttemptedTeamScopeFails() async throws {
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [.response(statusCode: 404)],
            "/v2/teams": [.response(statusCode: 200, body: singleTeamPage)],
            "/v9/projects": [
                .response(statusCode: 403, query: ["teamId": "team_fixture"]),
            ],
        ]
    )
    let client = VercelAPIClient(token: "fixture-token", transport: transport)

    do {
        _ = try await client.listAccessibleProjects()
        Issue.record("Expected team-scope discovery failure")
    } catch let error as VercelAPIError {
        #expect(error == .permissionDenied(status: 403))
    }

    let requests = await transport.requests
    #expect(requests.count == 3)
}

@Test func clientRejectsRepeatedDiscoveryCursor() async throws {
    let repeatedPage = #"{"teams":[],"pagination":{"next":"repeated"}}"#
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [.response(statusCode: 404)],
            "/v2/teams": [
                .response(statusCode: 200, body: repeatedPage),
                .response(statusCode: 200, body: repeatedPage),
            ],
        ]
    )

    do {
        _ = try await VercelAPIClient(token: "fixture-token", transport: transport).listAccessibleProjects()
        Issue.record("Expected repeated-cursor failure")
    } catch let error as VercelAPIError {
        #expect(error == .malformedResponse(endpoint: "/v2/teams"))
    }
}

@Test func clientRejectsMalformedDiscoveryCursor() async throws {
    let malformedPage = #"{"teams":[],"pagination":{"next":true}}"#
    let transport = FixtureTransport(
        responses: [
            "/v2/user": [.response(statusCode: 404)],
            "/v2/teams": [.response(statusCode: 200, body: malformedPage)],
        ]
    )

    do {
        _ = try await VercelAPIClient(token: "fixture-token", transport: transport).listAccessibleProjects()
        Issue.record("Expected malformed-cursor failure")
    } catch let error as VercelAPIError {
        #expect(error == .malformedResponse(endpoint: "/v2/teams"))
    }
}

private func expectDiscoveryRequests(_ requests: [URLRequest]) {
    #expect(requests.count == 7)
    let teamRequests = requests.filter { $0.url?.path == "/v2/teams" }
    #expect(teamRequests.count == 2)
    #expect(queryValue("limit", in: teamRequests[0]) == "100")
    #expect(queryValue("until", in: teamRequests[1]) == "123")

    let projectRequests = requests.filter { $0.url?.path == "/v9/projects" }
    #expect(projectRequests.count == 4)
    #expect(queryValue("teamId", in: projectRequests[0]) == nil)
    #expect(queryValue("teamId", in: projectRequests[1]) == "team_fixture")
    #expect(queryValue("until", in: projectRequests[2]) == "cursor-two")
    #expect(queryValue("teamId", in: projectRequests[3]) == "team_second")
}

private let emptyTeamsPage = #"{"teams":[],"pagination":{"next":null}}"#
private let singleTeamPage = #"""
{"teams":[{"id":"team_fixture","name":"Fixture Team","slug":"fixture-team"}],"pagination":{"next":null}}
"""#
private let singleTeamProjectPage = #"""
{"projects":[{"id":"prj_team_fixture","name":"Team Project"}],"pagination":{"next":null}}
"""#
private let personalProjectPage = #"""
{"projects":[{"id":"prj_personal_fixture","name":"Personal Project"}],"pagination":{"next":null}}
"""#
private let projectsWithUpdatedAtPage = #"""
{
  "projects": [
    {"id":"missing","name":"Aardvark"},
    {"id":"older","name":"Older","updatedAt":1785000000000},
    {"id":"same-b","name":"beta","updatedAt":1785500000000},
    {"id":"same-a","name":"Alpha","updatedAt":1785500000000},
    {"id":"newest","name":"Newest","updatedAt":1786000000000}
  ],
  "pagination":{"next":null}
}
"""#
