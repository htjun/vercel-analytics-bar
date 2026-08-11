import Foundation
import VercelAnalyticsCore

enum DemoFixtureError: Error, Equatable, LocalizedError, Sendable {
    case missing
    case unreadable
    case invalid

    var errorDescription: String? {
        switch self {
        case .missing:
            "The demo fixture is missing from the app bundle."
        case .unreadable:
            "The demo fixture could not be read."
        case .invalid:
            "The demo fixture contains invalid analytics data."
        }
    }
}

enum DemoFixtureLoader {
    static let resourceName = "DemoFixture"
    static let resourceExtension = "json"

    static func load(from bundle: Bundle = .main) throws -> AnalyticsSnapshot {
        try load(from: bundle.url(forResource: resourceName, withExtension: resourceExtension))
    }

    static func load(from url: URL?) throws -> AnalyticsSnapshot {
        guard let url else { throw DemoFixtureError.missing }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DemoFixtureError.unreadable
        }

        return try decode(data)
    }

    static func decode(_ data: Data) throws -> AnalyticsSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(AnalyticsSnapshot.self, from: data)
        } catch {
            throw DemoFixtureError.invalid
        }
    }
}

struct DemoAnalyticsSnapshotProvider: AnalyticsSnapshotProviding {
    private enum Source: Sendable {
        case snapshot(AnalyticsSnapshot)
        case failure(DemoFixtureError)
    }

    private let source: Source

    var initialRange: VercelAnalyticsRange {
        switch source {
        case let .snapshot(snapshot):
            snapshot.range
        case .failure:
            .last7Days
        }
    }

    init(snapshot: AnalyticsSnapshot) {
        source = .snapshot(snapshot)
    }

    init(error: DemoFixtureError) {
        source = .failure(error)
    }

    func snapshot(for range: VercelAnalyticsRange) async throws -> AnalyticsSnapshot {
        switch source {
        case let .snapshot(snapshot):
            AnalyticsSnapshot(
                projectName: snapshot.projectName,
                range: range,
                visitors: snapshot.visitors,
                pageViews: snapshot.pageViews,
                series: snapshot.series,
                topPages: snapshot.topPages,
                topReferrers: snapshot.topReferrers,
                last24HoursVisitors: snapshot.last24HoursVisitors,
                refreshedAt: snapshot.refreshedAt
            )
        case let .failure(error):
            throw error
        }
    }
}

@MainActor
enum DemoAppModelFactory {
    static func makeModel(bundle: Bundle = .main) -> AppModel {
        let provider: DemoAnalyticsSnapshotProvider
        do {
            provider = try DemoAnalyticsSnapshotProvider(snapshot: DemoFixtureLoader.load(from: bundle))
        } catch let error as DemoFixtureError {
            provider = DemoAnalyticsSnapshotProvider(error: error)
        } catch {
            provider = DemoAnalyticsSnapshotProvider(error: .invalid)
        }

        return makeModel(provider: provider, initialRange: provider.initialRange)
    }

    static func makeModel(
        provider: any AnalyticsSnapshotProviding,
        initialRange: VercelAnalyticsRange
    ) -> AppModel {
        AppModel(
            provider: provider,
            credentialStore: DemoCredentialStore(),
            accountDataStore: DemoAccountDataStore(analyticsRange: initialRange),
            snapshotCacheStore: DemoSnapshotCacheStore(),
            launchAtLoginManager: DemoLaunchAtLoginManager(),
            tokenValidator: { _ in }
        )
    }
}

private final class DemoCredentialStore: VercelCredentialStore {
    private var token: String?

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

private final class DemoAccountDataStore: VercelAccountDataStore {
    private var projectSelection = ProjectSelection.empty
    private var analyticsRange: VercelAnalyticsRange

    init(analyticsRange: VercelAnalyticsRange) {
        self.analyticsRange = analyticsRange
    }

    func readProjectSelection() throws -> ProjectSelection {
        projectSelection
    }

    func saveProjectSelection(_ selection: ProjectSelection) throws {
        projectSelection = selection
    }

    func readAnalyticsRange() throws -> VercelAnalyticsRange {
        analyticsRange
    }

    func saveAnalyticsRange(_ range: VercelAnalyticsRange) throws {
        analyticsRange = range
    }

    func clear() throws {
        projectSelection = .empty
        analyticsRange = .last7Days
    }
}

private final class DemoSnapshotCacheStore: AnalyticsSnapshotCacheStore {
    private var entries: [SnapshotCacheEntry] = []

    func read() throws -> [SnapshotCacheEntry] {
        entries
    }

    func write(_ entries: [SnapshotCacheEntry]) throws {
        self.entries = entries
    }

    func clear() throws {
        entries = []
    }
}

private struct DemoLaunchAtLoginManager: LaunchAtLoginManaging {
    let status = LaunchAtLoginStatus.unavailable

    func setEnabled(_: Bool) throws {}
}
