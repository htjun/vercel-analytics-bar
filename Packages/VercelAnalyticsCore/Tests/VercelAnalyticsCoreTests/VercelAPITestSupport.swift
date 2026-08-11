import Foundation
import VercelAnalyticsCore

actor FixtureTransport: VercelHTTPTransport {
    private var responses: [String: [FixtureResponse]]
    private(set) var requests: [URLRequest] = []

    init(responses: [String: [FixtureResponse]]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let path = request.url?.path, var pathResponses = responses[path], !pathResponses.isEmpty else {
            throw FixtureTransportError.missingResponse
        }

        let responseIndex = pathResponses.firstIndex { response in
            response.query?.allSatisfy { queryValue($0.key, in: request) == $0.value } == true
        } ?? pathResponses.firstIndex { $0.query == nil }
        guard let responseIndex else {
            throw FixtureTransportError.missingResponse
        }
        let response = pathResponses.remove(at: responseIndex)
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

struct FixtureResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let query: [String: String]?

    static func fixture(named name: String, query: [String: String]? = nil) throws -> FixtureResponse {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureTransportError.missingFixture
        }
        return try FixtureResponse(statusCode: 200, headers: [:], body: Data(contentsOf: url), query: query)
    }

    static func response(
        statusCode: Int,
        headers: [String: String] = [:],
        body: String = "{}",
        query: [String: String]? = nil
    ) -> FixtureResponse {
        FixtureResponse(statusCode: statusCode, headers: headers, body: Data(body.utf8), query: query)
    }
}

enum FixtureTransportError: Error {
    case missingFixture
    case missingResponse
    case invalidResponse
}

struct AggregateFixturePoint: Sendable {
    let timestamp: Date
    let visitors: Int
    let pageViews: Int
}

func queryValue(_ name: String, in request: URLRequest) -> String? {
    guard let url = request.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == name }?
        .value
}

func date(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: value) else {
        throw FixtureTransportError.missingFixture
    }
    return date
}

func aggregateFixture(points: [AggregateFixturePoint]) throws -> FixtureResponse {
    let payload: [String: Any] = [
        "version": 1,
        "query": [
            "since": iso8601String(points[0].timestamp),
            "until": iso8601String(points[points.count - 1].timestamp),
            "groupBy": ["hour"],
            "filter": "environment eq 'production'",
        ],
        "data": points.map { point in
            [
                "timestamp": iso8601String(point.timestamp),
                "visitors": point.visitors,
                "pageviews": point.pageViews,
            ]
        },
    ]
    let body = try JSONSerialization.data(withJSONObject: payload)
    return FixtureResponse(statusCode: 200, headers: [:], body: body, query: nil)
}

private func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
