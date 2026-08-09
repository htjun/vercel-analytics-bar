import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelLoadsRenderedAnalyticsContentThroughFixtureTransport() async {
    let transport = StaticAnalyticsTransport()
    let project = VercelProject(id: "project-a", name: "Alpha")
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { token, selectedProject in
            VercelAnalyticsSnapshotProvider(
                token: token,
                project: selectedProject,
                now: { Date(timeIntervalSince1970: 1_785_628_800) },
                transport: transport
            )
        },
        tokenValidator: { _ in }
    )

    await model.connect(token: "fixture-token")
    await model.load()

    guard case let .loaded(snapshot) = model.state else {
        Issue.record("Expected loaded analytics content")
        return
    }
    #expect(snapshot.projectName == "Alpha")
    #expect(snapshot.range == .last7Days)
    #expect(snapshot.visitors.value == 165)
    #expect(snapshot.pageViews.value == 284)
    #expect(snapshot.series.count == 1)
    #expect(snapshot.topPages == [
        VercelAnalyticsBreakdown(label: "/products", visitors: 80, pageViews: 128),
    ])
    #expect(snapshot.topReferrers == [
        VercelAnalyticsBreakdown(label: "google.com", visitors: 48, pageViews: 64),
    ])
    #expect(model.abbreviatedVisitors == "24")
    #expect(await transport.requests.count == 6)
}

private actor StaticAnalyticsTransport: VercelHTTPTransport {
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let body = try responseBody(for: request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw StaticAnalyticsTransportError.invalidResponse
        }
        return (Data(body.utf8), response)
    }

    private func responseBody(for request: URLRequest) throws -> String {
        switch request.url?.path {
        case "/v1/query/web-analytics/visits/count":
            countResponseBody
        case "/v1/query/web-analytics/visits/aggregate":
            aggregateResponseBody(for: queryValue("by", in: request))
        default:
            throw StaticAnalyticsTransportError.unhandledRequest
        }
    }

    private func aggregateResponseBody(for dimension: String?) -> String {
        switch dimension {
        case "requestPath":
            pageResponseBody
        case "referrerHostname":
            referralResponseBody
        default:
            seriesResponseBody
        }
    }

    private var countResponseBody: String {
        "{\(responseQuery),\"data\":{\"visitors\":165,\"pageviews\":284}}"
    }

    private var pageResponseBody: String {
        "{\(responseQuery),\"data\":[{\"requestPath\":\"/products\",\"visitors\":80,\"pageviews\":128}]}"
    }

    private var referralResponseBody: String {
        "{\(responseQuery),\"data\":[{\"referrerHostname\":\"google.com\",\"visitors\":48,\"pageviews\":64}]}"
    }

    private var seriesResponseBody: String {
        """
        {\(responseQuery),"data":[
          {"timestamp":"2026-08-01T00:00:00.000Z","visitors":20,"pageviews":34},
          {"timestamp":"2026-08-02T00:00:00.000Z","visitors":24,"pageviews":41}
        ]}
        """
    }

    private var responseQuery: String {
        #""query":{"since":"2026-07-26T00:00:00.000Z","until":"2026-08-02T00:00:00.000Z"}"#
    }
}

private enum StaticAnalyticsTransportError: Error {
    case unhandledRequest
    case invalidResponse
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    guard let url = request.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == name }?
        .value
}
