import Foundation
import Testing
@testable import VercelAnalyticsCore

@Test func secureTransportUsesEphemeralCacheFreeCookieFreeConfiguration() {
    let configuration = URLSessionVercelHTTPTransport.secureConfiguration()

    #expect(configuration.identifier == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(!configuration.httpShouldSetCookies)
    #expect(configuration.timeoutIntervalForRequest == 30)
    #expect(configuration.timeoutIntervalForResource == 60)
}

@Test func secureTransportRejectsRedirects() throws {
    let delegate = RedirectRejectingURLSessionDelegate()
    let session = URLSession(configuration: .ephemeral)
    let sourceURL = try #require(URL(string: "https://api.vercel.com/v2/teams"))
    let targetURL = try #require(URL(string: "https://example.com/redirect"))
    let response = try #require(HTTPURLResponse(url: sourceURL, statusCode: 302, httpVersion: nil, headerFields: nil))
    let task = session.dataTask(with: sourceURL)
    var redirectedRequest: URLRequest? = URLRequest(url: targetURL)

    delegate.urlSession(
        session,
        task: task,
        willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: targetURL)
    ) { redirectedRequest = $0 }

    #expect(redirectedRequest == nil)
    session.invalidateAndCancel()
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
    let permissionTransport = try FixtureTransport(
        responses: [
            "/v2/user": [.fixture(named: "authenticated-user")],
            "/v2/teams": [
                .response(statusCode: 200, body: #"{"teams":[],"pagination":{"next":null}}"#),
            ],
            "/v9/projects": [.response(statusCode: 403, body: "private-response")],
        ]
    )
    do {
        _ = try await VercelAPIClient(
            token: "fixture-token",
            transport: permissionTransport
        ).listAccessibleProjects()
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

@Test func clientRejectsPaginationBeyondOneHundredPages() async throws {
    var teamResponses: [FixtureResponse] = []
    for pageIndex in 0 ..< 100 {
        let cursor = "cursor-\(pageIndex)"
        let query = pageIndex == 0 ? nil : ["until": "cursor-\(pageIndex - 1)"]
        teamResponses.append(
            .response(
                statusCode: 200,
                body: #"{"teams":[],"pagination":{"next":"\#(cursor)"}}"#,
                query: query
            )
        )
    }
    let transport = try FixtureTransport(
        responses: [
            "/v2/user": [.fixture(named: "authenticated-user")],
            "/v2/teams": teamResponses,
        ]
    )

    do {
        _ = try await VercelAPIClient(token: "fixture-token", transport: transport).listAccessibleProjects()
        Issue.record("Expected the pagination limit to reject the response")
    } catch let error as VercelAPIError {
        #expect(error == .malformedResponse(endpoint: "/v2/teams"))
    }
}
