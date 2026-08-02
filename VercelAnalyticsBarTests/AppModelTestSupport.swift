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
