import Foundation
import Testing
import VercelAnalyticsCore
@testable import VercelAnalyticsBar

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

    try UserDefaultsVercelAccountDataStore(
        userDefaults: userDefaults,
        applicationSupportURL: supportURL
    ).clear()

    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.selectedProjectIDsKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.currentProjectIDKey) == nil)
    #expect(userDefaults.object(forKey: UserDefaultsVercelAccountDataStore.analyticsRangeKey) == nil)
    #expect(FileManager.default.fileExists(atPath: cacheURL.path) == false)
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

    init(hasData: Bool = false) {
        self.hasData = hasData
    }

    func clear() throws {
        hasData = false
    }
}
