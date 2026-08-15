import Foundation
import Observation
import VercelAnalyticsCore

struct DemoMetricOffsets: Equatable, Sendable {
    static let zero = DemoMetricOffsets(visitors: 0, pageViews: 0)

    let visitors: Int
    let pageViews: Int

    func advanced() -> DemoMetricOffsets {
        DemoMetricOffsets(
            visitors: visitors.saturatingAdding(7),
            pageViews: pageViews.saturatingAdding(13)
        )
    }
}

@MainActor
@Observable
final class DemoMetricTicker {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private(set) var offsets = DemoMetricOffsets.zero
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool {
        task != nil
    }

    init(sleep: @escaping Sleep = { duration in
        try await Task.sleep(for: duration)
    }) {
        self.sleep = sleep
    }

    func start() {
        stop()
        task = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do {
                    try await sleep(.seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else { return }
                offsets = offsets.advanced()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        offsets = .zero
    }
}

extension AnalyticsCardPresentation {
    func applyingDemoOffsets(_ offsets: DemoMetricOffsets) -> AnalyticsCardPresentation {
        AnalyticsCardPresentation(
            projectName: projectName,
            selectedRange: selectedRange,
            visitors: visitors.applyingDemoOffset(offsets.visitors),
            pageViews: pageViews.applyingDemoOffset(offsets.pageViews),
            series: series,
            topPages: topPages,
            topReferrers: topReferrers,
            updatedText: updatedText,
            dashboardURL: dashboardURL
        )
    }
}

private extension AnalyticsCardMetric {
    func applyingDemoOffset(_ offset: Int) -> AnalyticsCardMetric {
        AnalyticsCardMetric(
            label: label,
            value: value.saturatingAdding(offset),
            comparisonText: comparisonText,
            trend: trend
        )
    }
}

private extension Int {
    func saturatingAdding(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        guard overflow else { return result }
        return other >= 0 ? .max : .min
    }
}

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
    static let projects = [
        VercelProject(id: "node-storefront", name: "node-storefront"),
        VercelProject(id: "checkout-worker", name: "checkout-worker"),
        VercelProject(id: "commerce-api", name: "commerce-api"),
        VercelProject(id: "product-docs", name: "product-docs"),
        VercelProject(id: "storefront-design-system", name: "storefront-design-system"),
    ]

    private static let projectSelection = ProjectSelection(
        selectedProjectIDs: Set(projects.map(\.id)),
        currentProjectID: "node-storefront"
    )

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
            initialProjects: projects,
            credentialStore: DemoCredentialStore(),
            accountDataStore: DemoAccountDataStore(
                projectSelection: projectSelection,
                analyticsRange: initialRange
            ),
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
    private var projectSelection: ProjectSelection
    private var analyticsRange: VercelAnalyticsRange

    init(projectSelection: ProjectSelection, analyticsRange: VercelAnalyticsRange) {
        self.projectSelection = projectSelection
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
