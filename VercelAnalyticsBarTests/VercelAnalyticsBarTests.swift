import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelLoadsSnapshotThroughInjectedProvider() async {
    let expected = AnalyticsSnapshot.fixture
    let provider = ControlledSnapshotProvider()
    let model = AppModel(
        provider: provider,
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore()
    )

    #expect(model.state == .idle)

    let loadTask = Task {
        await model.load()
    }
    await provider.waitUntilRequested()

    #expect(model.state == .loading)
    #expect(await provider.requestedRanges == [.last7Days])

    await provider.succeed(with: expected)
    await loadTask.value

    #expect(model.state == .loaded(expected))
}

@MainActor
@Test func appModelExposesProviderFailure() async {
    let provider = ControlledSnapshotProvider()
    let model = AppModel(
        provider: provider,
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore()
    )

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
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        tokenValidator: { token in
            await validator.validate(token)
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
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
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
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
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
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        tokenValidator: { token in
            await validator.validate(token)
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
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")

    #expect(model.projectState == .loaded([
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-z", name: "Zebra", teamID: "team", teamName: "Team"),
    ]))
    #expect(model.selectedProjectIDs == ["project-a"])
    #expect(model.currentProjectID == "project-a")
    #expect(accountDataStore.selectedProjectIDs == ["project-a"])
    #expect(accountDataStore.currentProjectID == "project-a")
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
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    model.setProjectSelected("project-a", selected: false)
    model.setProjectSelected("project-b", selected: false)

    #expect(model.selectedProjectIDs == ["project-b"])
    #expect(model.currentProjectID == "project-b")
    #expect(accountDataStore.selectedProjectIDs == ["project-b"])
    #expect(accountDataStore.currentProjectID == "project-b")
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
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")

    #expect(model.projects(matching: "acme").map(\.id) == ["project-team"])
    #expect(model.selectedProjects(matching: "").map(\.id) == ["project-personal"])
    #expect(model.teamMetadata(for: projects[0]) == "Personal account")
    #expect(model.teamMetadata(for: projects[1]) == "Acme")
}

@MainActor
@Test func appModelFiltersSelectedProjectsByVisibleNameOnly() async {
    let projects = [
        VercelProject(id: "project-site", name: "example-site", teamID: "team", teamName: "Example Team"),
        VercelProject(id: "project-docs", name: "docs-site", teamID: "team", teamName: "Example Team"),
    ]
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    model.setProjectSelected("project-site", selected: true)

    #expect(model.selectedProjects(matching: "docs").map(\.id) == ["project-docs"])
    #expect(model.selectedProjects(matching: "example").map(\.id) == ["project-site"])
}

@MainActor
@Test func appModelSwitchesProjectsWithCachedFirstRefresh() async {
    let projects = [
        VercelProject(id: "project-alpha", name: "Alpha"),
        VercelProject(id: "project-beta", name: "Beta"),
    ]
    let accountDataStore = InMemoryAccountDataStore()
    let alphaProvider = ControlledSnapshotProvider()
    let betaProvider = ControlledSnapshotProvider()
    let initialRefreshDate = Date(timeIntervalSince1970: 1_785_549_600)
    let alphaSnapshot = makeAnalyticsSnapshot(
        projectName: "Alpha", visitors: 100, pageViews: 200, last24HoursVisitors: 11, refreshedAt: initialRefreshDate
    )
    let refreshedAlphaSnapshot = makeAnalyticsSnapshot(
        projectName: "Alpha", visitors: 101, pageViews: 202, last24HoursVisitors: 12,
        refreshedAt: initialRefreshDate.addingTimeInterval(60)
    )
    let betaSnapshot = makeAnalyticsSnapshot(
        projectName: "Beta", visitors: 300, pageViews: 500, last24HoursVisitors: 22, refreshedAt: initialRefreshDate
    )
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: accountDataStore,
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        analyticsProviderFactory: { _, project in
            project.id == "project-alpha" ? alphaProvider : betaProvider
        },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    model.setProjectSelected("project-beta", selected: true)

    let alphaLoadTask = Task { await model.load() }
    await alphaProvider.waitUntilRequested()
    await alphaProvider.succeed(with: alphaSnapshot)
    await alphaLoadTask.value

    let betaSwitchTask = Task { await model.selectProject("project-beta") }
    await betaProvider.waitUntilRequested()
    #expect(model.currentProjectID == "project-beta")
    #expect(model.state == .loading)
    await betaProvider.succeed(with: betaSnapshot)
    await betaSwitchTask.value

    let alphaSwitchTask = Task { await model.selectProject("project-alpha") }
    await alphaProvider.waitUntilRequested()
    #expect(model.currentProjectID == "project-alpha")
    #expect(model.state == .loaded(alphaSnapshot))
    #expect(model.abbreviatedVisitors == "11")

    await alphaProvider.succeed(with: refreshedAlphaSnapshot)
    await alphaSwitchTask.value

    #expect(model.state == .loaded(refreshedAlphaSnapshot))
    #expect(model.abbreviatedVisitors == "12")
    #expect(accountDataStore.currentProjectID == "project-alpha")
}

@MainActor
@Test func appModelLoadsLiveSnapshotForCurrentSelectedProject() async {
    let projects = [
        VercelProject(id: "project-z", name: "Zebra"),
        VercelProject(id: "project-a", name: "Alpha"),
    ]
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        analyticsProviderFactory: { _, project in
            FixtureAnalyticsSnapshotProvider(
                value: AnalyticsSnapshot(
                    projectName: project.name,
                    range: .last7Days,
                    visitors: AnalyticsMetric(label: "Visitors", value: 12847, previousValue: 12000),
                    pageViews: AnalyticsMetric(label: "Page Views", value: 21490, previousValue: 20000),
                    series: [],
                    last24HoursVisitors: 1890,
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
        range: .last7Days,
        visitors: AnalyticsMetric(label: "Visitors", value: 12847, previousValue: 12000),
        pageViews: AnalyticsMetric(label: "Page Views", value: 21490, previousValue: 20000),
        series: [],
        last24HoursVisitors: 1890,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )))
    #expect(model.abbreviatedVisitors == "1.9K")
}

@MainActor
@Test func appModelDefaultsPersistsAndReloadsAnalyticsRange() async {
    let accountDataStore = InMemoryAccountDataStore()
    let provider = ControlledSnapshotProvider()
    let model = AppModel(
        provider: provider,
        accountDataStore: accountDataStore,
        snapshotCacheStore: InMemorySnapshotCacheStore()
    )

    #expect(model.selectedRange == .last7Days)

    let selectionTask = Task {
        await model.selectAnalyticsRange(.last30Days)
    }
    await provider.waitUntilRequested()

    #expect(model.selectedRange == .last30Days)
    #expect(accountDataStore.analyticsRange == .last30Days)
    #expect(await provider.requestedRanges == [.last30Days])

    await provider.succeed(with: .fixture)
    await selectionTask.value

    let restoredModel = AppModel(provider: provider, accountDataStore: accountDataStore)
    #expect(restoredModel.selectedRange == .last30Days)
}

@MainActor
@Test func appModelDisconnectsCredentialAndAccountData() async {
    let credentialStore = InMemoryCredentialStore(token: "stored-token")
    let accountDataStore = InMemoryAccountDataStore(hasData: true)
    let model = AppModel(
        provider: FixtureAnalyticsSnapshotProvider(),
        credentialStore: credentialStore,
        accountDataStore: accountDataStore,
        snapshotCacheStore: InMemorySnapshotCacheStore()
    )

    await model.restoreConnection()
    model.disconnect()
    await model.refreshProjects()

    #expect(model.accountState == .disconnected)
    #expect(model.projectState == .failed("Connect a Vercel account before syncing projects."))
    #expect(model.activeToken == nil)
    #expect(credentialStore.token == nil)
    #expect(accountDataStore.hasData == false)
}
