import Foundation
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

enum SnapshotError: Error {
    case unavailable
}

actor ControlledSnapshotProvider: AnalyticsSnapshotProviding {
    private var resultContinuation: CheckedContinuation<AnalyticsSnapshot, any Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedRanges: [VercelAnalyticsRange] = []

    func snapshot(for range: VercelAnalyticsRange) async throws -> AnalyticsSnapshot {
        requestedRanges.append(range)
        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard resultContinuation == nil else { return }

        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func succeed(with snapshot: AnalyticsSnapshot) {
        resultContinuation?.resume(returning: snapshot)
        resultContinuation = nil
    }

    func fail(with error: any Error) {
        resultContinuation?.resume(throwing: error)
        resultContinuation = nil
    }
}

actor TokenValidationRecorder {
    private(set) var tokens: [String] = []

    func validate(_ token: String) {
        tokens.append(token)
    }
}

struct FixtureProjectListingProvider: VercelProjectListingProviding {
    let projects: [VercelProject]

    func listAccessibleProjects() async throws -> [VercelProject] {
        projects
    }
}

final class InMemoryCredentialStore: VercelCredentialStore {
    var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func read() throws -> String? {
        token
    }

    func save(_ token: String) throws {
        self.token = token
    }

    func delete() throws {
        token = nil
    }
}

final class InMemoryAccountDataStore: VercelAccountDataStore {
    var hasData: Bool
    var selectedProjectIDs: Set<String>
    var analyticsRange: VercelAnalyticsRange

    init(
        hasData: Bool = false,
        selectedProjectIDs: Set<String> = [],
        analyticsRange: VercelAnalyticsRange = .last7Days
    ) {
        self.hasData = hasData
        self.selectedProjectIDs = selectedProjectIDs
        self.analyticsRange = analyticsRange
    }

    func readSelectedProjectIDs() throws -> Set<String> {
        selectedProjectIDs
    }

    func saveSelectedProjectIDs(_ projectIDs: Set<String>) throws {
        selectedProjectIDs = projectIDs
    }

    func readAnalyticsRange() throws -> VercelAnalyticsRange {
        analyticsRange
    }

    func saveAnalyticsRange(_ range: VercelAnalyticsRange) throws {
        analyticsRange = range
    }

    func clear() throws {
        hasData = false
        selectedProjectIDs = []
        analyticsRange = .last7Days
    }
}

actor StaticAnalyticsTransport: VercelHTTPTransport {
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        let body: String
        switch request.url?.path {
        case "/v1/query/web-analytics/visits/count":
            body = """
            {
              "query": {
                "since": "2026-07-26T00:00:00.000Z",
                "until": "2026-08-02T00:00:00.000Z"
              },
              "data": {
                "visitors": 165,
                "pageviews": 284
              }
            }
            """
        case "/v1/query/web-analytics/visits/aggregate":
            body = """
            {
              "query": {
                "since": "2026-07-26T00:00:00.000Z",
                "until": "2026-08-02T00:00:00.000Z"
              },
              "data": [
                {
                  "timestamp": "2026-08-01T00:00:00.000Z",
                  "visitors": 20,
                  "pageviews": 34
                },
                {
                  "timestamp": "2026-08-02T00:00:00.000Z",
                  "visitors": 24,
                  "pageviews": 41
                }
              ]
            }
            """
        default:
            throw StaticAnalyticsTransportError.unhandledRequest
        }

        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw StaticAnalyticsTransportError.invalidResponse
        }
        return (Data(body.utf8), response)
    }
}

enum StaticAnalyticsTransportError: Error {
    case unhandledRequest
    case invalidResponse
}
