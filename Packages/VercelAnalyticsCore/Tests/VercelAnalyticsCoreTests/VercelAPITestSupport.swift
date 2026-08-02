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

struct FixtureResponse: Sendable {
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

enum FixtureTransportError: Error {
    case missingFixture
    case missingResponse
    case invalidResponse
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
