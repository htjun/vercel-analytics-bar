import Foundation
import Testing
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
    var currentProjectID: String?
    var analyticsRange: VercelAnalyticsRange

    init(
        hasData: Bool = false,
        selectedProjectIDs: Set<String> = [],
        currentProjectID: String? = nil,
        analyticsRange: VercelAnalyticsRange = .last7Days
    ) {
        self.hasData = hasData
        self.selectedProjectIDs = selectedProjectIDs
        self.currentProjectID = currentProjectID
        self.analyticsRange = analyticsRange
    }

    func readSelectedProjectIDs() throws -> Set<String> {
        selectedProjectIDs
    }

    func saveSelectedProjectIDs(_ projectIDs: Set<String>) throws {
        selectedProjectIDs = projectIDs
    }

    func readCurrentProjectID() throws -> String? {
        currentProjectID
    }

    func saveCurrentProjectID(_ projectID: String?) throws {
        currentProjectID = projectID
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
        currentProjectID = nil
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

func makeAnalyticsSnapshot(
    projectName: String,
    visitors: Int,
    pageViews: Int,
    last24HoursVisitors: Int,
    refreshedAt: Date
) -> AnalyticsSnapshot {
    AnalyticsSnapshot(
        projectName: projectName,
        range: .last7Days,
        visitors: AnalyticsMetric(label: "Visitors", value: visitors, previousValue: visitors * 9 / 10),
        pageViews: AnalyticsMetric(label: "Page Views", value: pageViews, previousValue: pageViews * 9 / 10),
        series: [],
        last24HoursVisitors: last24HoursVisitors,
        refreshedAt: refreshedAt
    )
}

@Test func accountDataStoreClearsPreferencesAndCache() throws {
    let suiteName = "VercelAnalyticsBarTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    let supportURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheURL = supportURL
        .appendingPathComponent("VercelAnalyticsBar", isDirectory: true)
        .appendingPathComponent("Cache", isDirectory: true)

    defer {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: supportURL)
    }

    try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    userDefaults.set(["project-id"], forKey: UserDefaultsVercelAccountDataStore.selectedProjectIDsKey)
    userDefaults.set("project-id", forKey: UserDefaultsVercelAccountDataStore.currentProjectIDKey)
    userDefaults.set("last7Days", forKey: UserDefaultsVercelAccountDataStore.analyticsRangeKey)

    let store = UserDefaultsVercelAccountDataStore(
        userDefaults: userDefaults,
        applicationSupportURL: supportURL
    )
    try store.saveSelectedProjectIDs(["project-b", "project-a"])
    #expect(try store.readSelectedProjectIDs() == ["project-a", "project-b"])
    try store.saveCurrentProjectID("project-b")
    #expect(try store.readCurrentProjectID() == "project-b")
    #expect(try store.readAnalyticsRange() == .last7Days)
    try store.saveAnalyticsRange(.last30Days)
    #expect(try store.readAnalyticsRange() == .last30Days)

    try store.clear()

    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.selectedProjectIDsKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.currentProjectIDKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.analyticsRangeKey) == nil)
    #expect(FileManager.default.fileExists(atPath: cacheURL.path) == false)
}
