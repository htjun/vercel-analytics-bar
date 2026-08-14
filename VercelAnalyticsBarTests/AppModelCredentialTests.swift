import Foundation
import Security
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelReusesRestoredTokenWithoutAdditionalCredentialReads() async {
    let credentialStore = CountingCredentialStore(token: "stored-token")
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let model = AppModel(
        credentialStore: credentialStore,
        accountDataStore: InMemoryAccountDataStore(
            selectedProjectIDs: [project.id],
            currentProjectID: project.id
        ),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in FixtureAnalyticsSnapshotProvider() },
        tokenValidator: { _ in }
    )

    await model.restoreConnection()
    await model.refreshProjects()
    await model.load()
    await model.load()

    #expect(model.accountState == .connected)
    #expect(model.state == .loaded(.fixture))
    #expect(credentialStore.readCount == 1)
}

@MainActor
@Test func appModelExposesAndClearsTheConnectedAccountProfile() async {
    let profile = VercelAccountProfile(
        id: "user-fixture",
        name: "Fixture User",
        username: "fixture-user",
        avatarURL: URL(string: "https://api.vercel.com/www/avatar/fixture-avatar")
    )
    let discovery = VercelAccountDiscovery(
        profile: profile,
        projects: [VercelProject(id: "project-a", name: "Alpha")]
    )
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureAccountDiscoveryProvider(discovery: discovery) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")

    #expect(model.connectedAccount == profile)

    model.disconnect()

    #expect(model.connectedAccount == nil)
}

@MainActor
@Test func appModelClearsRuntimeTokenAfterFailedRestoration() async {
    let credentialStore = CountingCredentialStore(token: "invalid-token")
    let model = AppModel(
        credentialStore: credentialStore,
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: []) },
        tokenValidator: { _ in
            throw VercelAPIError.authentication(status: 403)
        }
    )

    await model.restoreConnection()
    await model.refreshProjects()

    #expect(model.accountState == .failed(.invalidToken))
    #expect(model.projectState == .failed("Connect a Vercel account before refreshing projects."))
    #expect(model.activeToken == nil)
    #expect(credentialStore.readCount == 1)
}

@MainActor
@Test func appModelMapsCredentialSaveFailuresToSafeStorageState() async {
    let credentialStore = FailingCredentialStore(
        error: .keychainStatus(errSecMissingEntitlement)
    )
    let model = AppModel(
        credentialStore: credentialStore,
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        tokenValidator: { _ in }
    )

    await model.connect(token: "vercel-secret-token")

    #expect(model.accountState == .failed(.storageFailure))
    #expect(model.activeToken == nil)
    #expect(!AccountConnectionError.storageFailure.localizedDescription.contains("vercel-secret-token"))
}

@MainActor
@Test func appModelMapsCredentialReadFailuresToSafeStorageState() async {
    let model = AppModel(
        credentialStore: FailingCredentialStore(error: .keychainStatus(errSecMissingEntitlement)),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        tokenValidator: { _ in }
    )

    await model.restoreConnection()

    #expect(model.accountState == .failed(.storageFailure))
    #expect(model.activeToken == nil)
}

@MainActor
@Test func appModelMapsCredentialDeleteFailuresToSafeStorageState() {
    let model = AppModel(
        credentialStore: FailingCredentialStore(error: .keychainStatus(errSecMissingEntitlement)),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        tokenValidator: { _ in }
    )

    model.disconnect()

    #expect(model.accountState == .failed(.storageFailure))
    #expect(model.activeToken == nil)
}

private final class CountingCredentialStore: VercelCredentialStore {
    private(set) var readCount = 0
    private var token: String?

    init(token: String?) {
        self.token = token
    }

    func read() throws -> String? {
        readCount += 1
        return token
    }

    func save(_ token: String) throws {
        self.token = token
    }

    func delete() throws {
        token = nil
    }
}

private struct FixtureAccountDiscoveryProvider: VercelProjectListingProviding {
    let discovery: VercelAccountDiscovery

    func listAccessibleProjects() async throws -> [VercelProject] {
        discovery.projects
    }

    func discoverAccount() async throws -> VercelAccountDiscovery {
        discovery
    }
}

private struct FailingCredentialStore: VercelCredentialStore {
    let error: CredentialStoreError

    func read() throws -> String? {
        throw error
    }

    func save(_: String) throws {
        throw error
    }

    func delete() throws {
        throw error
    }
}
