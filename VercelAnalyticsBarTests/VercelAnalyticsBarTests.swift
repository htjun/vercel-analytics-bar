import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelLoadsSnapshotThroughInjectedProvider() async {
    let expected = AnalyticsSnapshot.fixture
    let provider = ControlledSnapshotProvider()
    let model = AppModel(provider: provider)

    #expect(model.state == .idle)

    let loadTask = Task {
        await model.load()
    }
    await provider.waitUntilRequested()

    #expect(model.state == .loading)

    await provider.succeed(with: expected)
    await loadTask.value

    #expect(model.state == .loaded(expected))
}

@MainActor
@Test func appModelExposesProviderFailure() async {
    let provider = ControlledSnapshotProvider()
    let model = AppModel(provider: provider)

    let loadTask = Task {
        await model.load()
    }
    await provider.waitUntilRequested()
    await provider.fail(with: SnapshotError.unavailable)
    await loadTask.value

    guard case let .failed(message) = model.state else {
        Issue.record("Expected a failed state")
        return
    }

    #expect(message == SnapshotError.unavailable.localizedDescription)
}

@MainActor
@Test func appModelStoresOnlyValidatedToken() async {
    let credentialStore = InMemoryCredentialStore()
    let validator = TokenValidationRecorder()
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: credentialStore,
        tokenValidator: { token in
            try await validator.validate(token)
        }
    )

    await model.connect(token: "  valid-token  ")

    #expect(model.accountState == .connected)
    #expect(credentialStore.token == "valid-token")
    #expect(await validator.tokens == ["valid-token"])
}

@MainActor
@Test func appModelDoesNotStoreInvalidToken() async {
    let credentialStore = InMemoryCredentialStore()
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: credentialStore,
        tokenValidator: { _ in
            throw VercelAPIError.authentication(status: 403)
        }
    )

    await model.connect(token: "invalid-token")

    #expect(model.accountState == .failed(.invalidToken))
    #expect(credentialStore.token == nil)
}

@MainActor
@Test func appModelExposesInsufficientPermissionState() async {
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: InMemoryCredentialStore(),
        tokenValidator: { _ in
            throw VercelAPIError.permissionDenied(status: 403)
        }
    )

    await model.connect(token: "limited-token")

    #expect(model.accountState == .failed(.insufficientPermissions))
}

@MainActor
@Test func appModelRestoresValidatedTokenFromCredentialStore() async {
    let credentialStore = InMemoryCredentialStore(token: "stored-token")
    let validator = TokenValidationRecorder()
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: credentialStore,
        tokenValidator: { token in
            try await validator.validate(token)
        }
    )

    await model.restoreConnection()

    #expect(model.accountState == .connected)
    #expect(await validator.tokens == ["stored-token"])
}

@MainActor
@Test func appModelLoadsAndSortsAccountWideProjectList() async {
    let accountDataStore = InMemoryAccountDataStore()
    let projects = [
        VercelProject(id: "project-z", name: "Zebra", teamID: "team", teamName: "Team"),
        VercelProject(id: "project-a", name: "Alpha"),
    ]
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: accountDataStore,
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")

    #expect(model.projectState == .loaded([
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-z", name: "Zebra", teamID: "team", teamName: "Team"),
    ]))
    #expect(model.selectedProjectIDs == ["project-a"])
    #expect(accountDataStore.selectedProjectIDs == ["project-a"])
}

@MainActor
@Test func appModelRestoresSelectionAndKeepsOneProjectSelected() async {
    let accountDataStore = InMemoryAccountDataStore(selectedProjectIDs: ["project-a", "project-b"])
    let projects = [
        VercelProject(id: "project-b", name: "Beta"),
        VercelProject(id: "project-a", name: "Alpha"),
    ]
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: accountDataStore,
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    model.setProjectSelected("project-a", selected: false)
    model.setProjectSelected("project-b", selected: false)

    #expect(model.selectedProjectIDs == ["project-b"])
    #expect(accountDataStore.selectedProjectIDs == ["project-b"])
}

@MainActor
@Test func appModelFiltersProjectsAndShowsDuplicateTeamMetadata() async {
    let projects = [
        VercelProject(id: "project-personal", name: "Dashboard"),
        VercelProject(id: "project-team", name: "Dashboard", teamID: "team", teamName: "Acme"),
        VercelProject(id: "project-other", name: "Storefront"),
    ]
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: InMemoryCredentialStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")

    #expect(model.projects(matching: "acme").map(\.id) == ["project-team"])
    #expect(model.teamMetadata(for: projects[0]) == "Personal account")
    #expect(model.teamMetadata(for: projects[1]) == "Acme")
}

@MainActor
@Test func appModelLoadsLiveSnapshotForCurrentSelectedProject() async {
    let projects = [
        VercelProject(id: "project-z", name: "Zebra"),
        VercelProject(id: "project-a", name: "Alpha"),
    ]
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        analyticsProviderFactory: { _, project in
            FixtureAnalyticsSnapshotProvider(
                value: AnalyticsSnapshot(
                    projectName: project.name,
                    primaryMetric: AnalyticsMetric(label: "Visitors", value: 12847),
                    refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
                )
            )
        },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    await model.load()

    #expect(model.currentProject?.id == "project-a")
    #expect(model.state == .loaded(AnalyticsSnapshot(
        projectName: "Alpha",
        primaryMetric: AnalyticsMetric(label: "Visitors", value: 12847),
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )))
    #expect(model.abbreviatedVisitors == "12.8K")
}

@MainActor
@Test func appModelShowsEmptyStateWhenNoProjectIsSelected() async {
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: []) },
        analyticsProviderFactory: { _, _ in FixtureAnalyticsSnapshotProvider() },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    await model.load()

    #expect(model.state == .empty("Select a Vercel project in Settings to load analytics."))
}

@MainActor
@Test func appModelDisconnectsCredentialAndAccountData() async {
    let credentialStore = InMemoryCredentialStore(token: "stored-token")
    let accountDataStore = InMemoryAccountDataStore(hasData: true)
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: credentialStore,
        accountDataStore: accountDataStore
    )

    model.disconnect()

    #expect(model.accountState == .disconnected)
    #expect(credentialStore.token == nil)
    #expect(accountDataStore.hasData == false)
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

    try store.clear()

    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.selectedProjectIDsKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.currentProjectIDKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.analyticsRangeKey) == nil)
    #expect(FileManager.default.fileExists(atPath: cacheURL.path) == false)
}

@Test func accountConnectionErrorsProvideSafeRecoveryCopy() {
    let secret = "vercel-secret-token"

    for error in [AccountConnectionError.invalidToken, .insufficientPermissions] {
        #expect(error.localizedDescription.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
        #expect(error.localizedDescription.contains(secret) == false)
        #expect(error.recoverySuggestion?.contains(secret) == false)
    }
}

private enum SnapshotError: Error {
    case unavailable
}

private actor ControlledSnapshotProvider: AnalyticsSnapshotProviding {
    private var resultContinuation: CheckedContinuation<AnalyticsSnapshot, any Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func snapshot() async throws -> AnalyticsSnapshot {
        try await withCheckedThrowingContinuation { continuation in
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

private actor TokenValidationRecorder {
    private(set) var tokens: [String] = []

    func validate(_ token: String) {
        tokens.append(token)
    }
}

private struct FixtureProjectListingProvider: VercelProjectListingProviding {
    let projects: [VercelProject]

    func listAccessibleProjects() async throws -> [VercelProject] {
        projects
    }
}

private final class InMemoryCredentialStore: VercelCredentialStore {
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

private final class InMemoryAccountDataStore: VercelAccountDataStore {
    var hasData: Bool
    var selectedProjectIDs: Set<String>

    init(hasData: Bool = false, selectedProjectIDs: Set<String> = []) {
        self.hasData = hasData
        self.selectedProjectIDs = selectedProjectIDs
    }

    func readSelectedProjectIDs() throws -> Set<String> {
        selectedProjectIDs
    }

    func saveSelectedProjectIDs(_ projectIDs: Set<String>) throws {
        selectedProjectIDs = projectIDs
    }

    func clear() throws {
        hasData = false
        selectedProjectIDs = []
    }
}
