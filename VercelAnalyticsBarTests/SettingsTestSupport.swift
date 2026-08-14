import Foundation
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
func makeManualRefreshFixture() -> ManualRefreshFixture {
    let oldProfile = VercelAccountProfile(name: "Old Name", username: "old-user")
    let newProfile = VercelAccountProfile(name: "New Name", username: "new-user")
    let retainedProject = VercelProject(
        id: "project-retained",
        name: "Retained",
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let removedProject = VercelProject(id: "project-removed", name: "Removed")
    let newestProject = VercelProject(
        id: "project-new",
        name: "Newest",
        updatedAt: Date(timeIntervalSince1970: 300)
    )
    let discoveryProvider = ControlledAccountDiscoveryProvider(
        initialDiscovery: VercelAccountDiscovery(
            profile: oldProfile,
            projects: [removedProject, retainedProject]
        )
    )
    let analyticsProvider = ControlledSnapshotProvider()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(
            selectedProjectIDs: [retainedProject.id, removedProject.id],
            currentProjectID: retainedProject.id
        ),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in discoveryProvider },
        analyticsProviderFactory: { _, _ in analyticsProvider },
        tokenValidator: { _ in }
    )
    return ManualRefreshFixture(
        model: model,
        discoveryProvider: discoveryProvider,
        analyticsProvider: analyticsProvider,
        oldProfile: oldProfile,
        newProfile: newProfile,
        retainedProject: retainedProject,
        removedProject: removedProject,
        newestProject: newestProject
    )
}

struct ManualRefreshFixture {
    let model: AppModel
    let discoveryProvider: ControlledAccountDiscoveryProvider
    let analyticsProvider: ControlledSnapshotProvider
    let oldProfile: VercelAccountProfile
    let newProfile: VercelAccountProfile
    let retainedProject: VercelProject
    let removedProject: VercelProject
    let newestProject: VercelProject
}

struct SettingsFixtureAccountDiscoveryProvider: VercelProjectListingProviding {
    let discovery: VercelAccountDiscovery

    func listAccessibleProjects() async throws -> [VercelProject] {
        discovery.projects
    }

    func discoverAccount() async throws -> VercelAccountDiscovery {
        discovery
    }
}

struct FailingProjectListingProvider: VercelProjectListingProviding {
    let error: any Error & Sendable

    func listAccessibleProjects() async throws -> [VercelProject] {
        throw error
    }
}

actor PendingAccountDiscoveryProvider: VercelProjectListingProviding {
    private var continuation: CheckedContinuation<VercelAccountDiscovery, any Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func listAccessibleProjects() async throws -> [VercelProject] {
        try await discoverAccount().projects
    }

    func discoverAccount() async throws -> VercelAccountDiscovery {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func succeed(with discovery: VercelAccountDiscovery) {
        continuation?.resume(returning: discovery)
        continuation = nil
    }
}

actor ControlledAccountDiscoveryProvider: VercelProjectListingProviding {
    private let initialDiscovery: VercelAccountDiscovery
    private var refreshContinuation: CheckedContinuation<VercelAccountDiscovery, any Error>?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var discoveryRequestCount = 0

    init(initialDiscovery: VercelAccountDiscovery) {
        self.initialDiscovery = initialDiscovery
    }

    func listAccessibleProjects() async throws -> [VercelProject] {
        initialDiscovery.projects
    }

    func discoverAccount() async throws -> VercelAccountDiscovery {
        discoveryRequestCount += 1
        guard discoveryRequestCount > 1 else { return initialDiscovery }

        return try await withCheckedThrowingContinuation { continuation in
            refreshContinuation = continuation
            refreshWaiters.forEach { $0.resume() }
            refreshWaiters.removeAll()
        }
    }

    func waitUntilRefreshRequested() async {
        guard discoveryRequestCount < 2 else { return }
        await withCheckedContinuation { continuation in
            refreshWaiters.append(continuation)
        }
    }

    func succeed(with discovery: VercelAccountDiscovery) {
        refreshContinuation?.resume(returning: discovery)
        refreshContinuation = nil
    }

    func fail(with error: any Error) {
        refreshContinuation?.resume(throwing: error)
        refreshContinuation = nil
    }
}
