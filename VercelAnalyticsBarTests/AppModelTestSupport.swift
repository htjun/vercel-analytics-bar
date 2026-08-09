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
    var projectSelection: ProjectSelection
    var analyticsRange: VercelAnalyticsRange
    var failProjectSelectionSave = false

    var selectedProjectIDs: Set<String> {
        projectSelection.selectedProjectIDs
    }

    var currentProjectID: String? {
        projectSelection.currentProjectID
    }

    init(
        hasData: Bool = false,
        selectedProjectIDs: Set<String> = [],
        currentProjectID: String? = nil,
        analyticsRange: VercelAnalyticsRange = .last7Days
    ) {
        self.hasData = hasData
        projectSelection = ProjectSelection(
            selectedProjectIDs: selectedProjectIDs,
            currentProjectID: currentProjectID
        )
        self.analyticsRange = analyticsRange
    }

    func readProjectSelection() throws -> ProjectSelection {
        projectSelection
    }

    func saveProjectSelection(_ selection: ProjectSelection) throws {
        if failProjectSelectionSave {
            throw AccountDataStoreError.invalidProjectSelection
        }
        projectSelection = selection
    }

    func readAnalyticsRange() throws -> VercelAnalyticsRange {
        analyticsRange
    }

    func saveAnalyticsRange(_ range: VercelAnalyticsRange) throws {
        analyticsRange = range
    }

    func clear() throws {
        hasData = false
        projectSelection = .empty
        analyticsRange = .last7Days
    }
}

final class InMemorySnapshotCacheStore: AnalyticsSnapshotCacheStore {
    var entries: [SnapshotCacheEntry]

    init(entries: [SnapshotCacheEntry] = []) {
        self.entries = entries
    }

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

final class InMemoryLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus
    var failure: LaunchAtLoginError?

    init(status: LaunchAtLoginStatus = .disabled) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        if let failure {
            throw failure
        }
        status = enabled ? .enabled : .disabled
    }
}

final class MutableDateClock: @unchecked Sendable {
    private(set) var date: Date

    init(date: Date) {
        self.date = date
    }

    func now() -> Date {
        date
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }
}

actor ManualRefreshSleeper {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []
    private var isSleeping = false

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
        isSleeping = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        isSleeping = false
    }

    func waitUntilSleeping() async {
        guard !isSleeping else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct RefreshTestHarness {
    let provider: ControlledSnapshotProvider
    let clock: MutableDateClock
    let sleeper: ManualRefreshSleeper
    let cacheStore: InMemorySnapshotCacheStore
    let model: AppModel

    init(
        project: VercelProject = VercelProject(id: "project-alpha", name: "Alpha"),
        provider: ControlledSnapshotProvider = ControlledSnapshotProvider(),
        now: Date = Date(timeIntervalSince1970: 1_785_549_720),
        cacheEntries: [SnapshotCacheEntry] = []
    ) {
        let clock = MutableDateClock(date: now)
        let sleeper = ManualRefreshSleeper()
        let cacheStore = InMemorySnapshotCacheStore(entries: cacheEntries)

        self.provider = provider
        self.clock = clock
        self.sleeper = sleeper
        self.cacheStore = cacheStore
        model = AppModel(
            credentialStore: InMemoryCredentialStore(),
            accountDataStore: InMemoryAccountDataStore(),
            snapshotCacheStore: cacheStore,
            projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
            analyticsProviderFactory: { _, _ in provider },
            launchAtLoginManager: InMemoryLaunchAtLoginManager(),
            now: { clock.now() },
            sleep: { duration in try await sleeper.sleep(for: duration) },
            tokenValidator: { _ in }
        )
    }

    func connect() async {
        await model.connect(token: "valid-token")
    }
}

func makeAnalyticsSnapshot(
    projectName: String,
    visitors: Int,
    pageViews: Int,
    last24HoursVisitors: Int,
    refreshedAt: Date,
    topPages: [VercelAnalyticsBreakdown] = []
) -> AnalyticsSnapshot {
    AnalyticsSnapshot(
        projectName: projectName,
        range: .last7Days,
        visitors: AnalyticsMetric(label: "Visitors", value: visitors, previousValue: visitors * 9 / 10),
        pageViews: AnalyticsMetric(label: "Page Views", value: pageViews, previousValue: pageViews * 9 / 10),
        series: [],
        topPages: topPages,
        last24HoursVisitors: last24HoursVisitors,
        refreshedAt: refreshedAt
    )
}

@Test func accountDataStoreMigratesSelectionAndClearsPreferencesAndCache() throws {
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
    let migratedSelection = try store.readProjectSelection()
    #expect(migratedSelection.selectedProjectIDs == ["project-id"])
    #expect(migratedSelection.currentProjectID == "project-id")
    #expect(userDefaults.data(forKey: UserDefaultsVercelAccountDataStore.projectSelectionKey) != nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.selectedProjectIDsKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.currentProjectIDKey) == nil)

    let updatedSelection = ProjectSelection(
        selectedProjectIDs: ["project-a", "project-b"],
        currentProjectID: "project-b"
    )
    try store.saveProjectSelection(updatedSelection)
    #expect(try store.readProjectSelection() == updatedSelection)
    #expect(try store.readAnalyticsRange() == .last7Days)
    try store.saveAnalyticsRange(.last30Days)
    #expect(try store.readAnalyticsRange() == .last30Days)

    try store.clear()

    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.projectSelectionKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.selectedProjectIDsKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.currentProjectIDKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.analyticsRangeKey) == nil)
    #expect(FileManager.default.fileExists(atPath: cacheURL.path) == false)
}

@Test func accountDataStoreRejectsUnsupportedSelectionVersion() throws {
    let suiteName = "VercelAnalyticsBarTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let unsupportedRecord = Data(
        #"{"currentProjectID":"project-a","selectedProjectIDs":["project-a"],"version":2}"#.utf8
    )
    userDefaults.set(unsupportedRecord, forKey: UserDefaultsVercelAccountDataStore.projectSelectionKey)
    let store = UserDefaultsVercelAccountDataStore(userDefaults: userDefaults)

    #expect(throws: AccountDataStoreError.invalidProjectSelection) {
        try store.readProjectSelection()
    }
}

@Test func snapshotCacheStoreIsVersionedAndKeepsProjectRangeKeysSeparate() throws {
    let supportURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = FileAnalyticsSnapshotCacheStore(applicationSupportURL: supportURL)
    let refreshedAt = Date(timeIntervalSince1970: 1_785_549_600)
    let last7Days = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: refreshedAt,
        topPages: [VercelAnalyticsBreakdown(label: "/products", visitors: 80, pageViews: 128)]
    )
    let last30Days = AnalyticsSnapshot(
        projectName: "Alpha",
        range: .last30Days,
        visitors: AnalyticsMetric(label: "Visitors", value: 300, previousValue: 270),
        pageViews: AnalyticsMetric(label: "Page Views", value: 500, previousValue: 450),
        series: [],
        last24HoursVisitors: 22,
        refreshedAt: refreshedAt
    )
    let entries = [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: last7Days),
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: last30Days),
    ]

    defer {
        try? FileManager.default.removeItem(at: supportURL)
    }

    try store.write(entries)
    #expect(try store.read() == entries)

    let encodedCache = try JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL))
    let legacyCache = try #require(encodedCache as? [String: Any])
    let legacyEntries = try #require(legacyCache["entries"] as? [[String: Any]])
    var legacyEntry = try #require(legacyEntries.first)
    var legacySnapshot = try #require(legacyEntry["snapshot"] as? [String: Any])
    legacySnapshot.removeValue(forKey: "topPages")
    legacySnapshot.removeValue(forKey: "topReferrers")
    legacyEntry["snapshot"] = legacySnapshot
    let legacyData = try JSONSerialization.data(withJSONObject: [
        "version": FileAnalyticsSnapshotCacheStore.currentSchemaVersion,
        "entries": [legacyEntry],
    ])
    try legacyData.write(to: store.fileURL, options: .atomic)
    let migratedEntries = try store.read()
    #expect(migratedEntries.count == 1)
    #expect(migratedEntries.first?.snapshot.topPages == [])
    #expect(migratedEntries.first?.snapshot.topReferrers == [])

    try Data(#"{"version":999,"entries":[]}"#.utf8).write(to: store.fileURL, options: .atomic)
    #expect(try store.read() == [])
    #expect(FileManager.default.fileExists(atPath: store.fileURL.path) == false)
}
