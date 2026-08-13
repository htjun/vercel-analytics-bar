import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@Test func projectCatalogRestoresAndReconcilesUnavailableSelectionDeterministically() throws {
    let accountDataStore = InMemoryAccountDataStore(
        selectedProjectIDs: ["unavailable-project"],
        currentProjectID: "unavailable-project"
    )
    var catalog = ProjectCatalog(persistence: accountDataStore)

    try catalog.restore()
    try catalog.reconcile(with: [
        VercelProject(id: "project-b", name: "Beta"),
        VercelProject(id: "project-a", name: "Alpha"),
    ])

    #expect(catalog.projects.map(\.id) == ["project-a", "project-b"])
    #expect(catalog.selectedProjectIDs.isEmpty)
    #expect(catalog.currentProjectID == nil)
    #expect(accountDataStore.projectSelection == catalog.selection)
    #expect(accountDataStore.projectSelectionSaveAttempts == [catalog.selection])
}

@Test func projectCatalogRestoresEmptySelectionWhenPersistenceReadFails() {
    let accountDataStore = InMemoryAccountDataStore(
        selectedProjectIDs: ["project-a"],
        currentProjectID: "project-a"
    )
    accountDataStore.failProjectSelectionRead = true
    var catalog = ProjectCatalog(persistence: accountDataStore)

    #expect(throws: AccountDataStoreError.invalidProjectSelection) {
        try catalog.restore()
    }

    #expect(catalog.selection == .empty)
}

@Test func projectCatalogRollsBackReconciliationWhenPersistenceFails() throws {
    let accountDataStore = InMemoryAccountDataStore(
        selectedProjectIDs: ["project-a"],
        currentProjectID: "project-a"
    )
    var catalog = ProjectCatalog(persistence: accountDataStore)
    try catalog.restore()
    try catalog.reconcile(with: [
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-b", name: "Beta"),
    ])
    let committedProjects = catalog.projects
    let committedSelection = catalog.selection
    accountDataStore.failProjectSelectionSave = true

    #expect(throws: AccountDataStoreError.invalidProjectSelection) {
        try catalog.reconcile(with: [VercelProject(id: "project-b", name: "Beta")])
    }

    #expect(catalog.projects == committedProjects)
    #expect(catalog.selection == committedSelection)
    #expect(accountDataStore.projectSelection == committedSelection)
    #expect(accountDataStore.projectSelectionSaveAttempts.last == ProjectSelection(
        selectedProjectIDs: [],
        currentProjectID: nil
    ))
}

@Test func projectCatalogPersistsSelectionIntentsAndSkipsNoOps() throws {
    let accountDataStore = InMemoryAccountDataStore(
        selectedProjectIDs: ["project-a"],
        currentProjectID: "project-a"
    )
    var catalog = ProjectCatalog(persistence: accountDataStore)
    try catalog.restore()
    try catalog.reconcile(with: [
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-b", name: "Beta"),
    ])

    #expect(try catalog.setProject("project-b", selected: true))
    #expect(try catalog.selectCurrentProject("project-b"))
    #expect(catalog.selectedProjectIDs == ["project-a", "project-b"])
    #expect(catalog.currentProjectID == "project-b")
    #expect(accountDataStore.projectSelection == catalog.selection)

    let saveCount = accountDataStore.projectSelectionSaveAttempts.count
    #expect(try !catalog.setProject("missing-project", selected: true))
    #expect(try !catalog.selectCurrentProject("project-b"))
    #expect(accountDataStore.projectSelectionSaveAttempts.count == saveCount)

    #expect(try catalog.setProject("project-a", selected: false))
    let finalSelectionSaveCount = accountDataStore.projectSelectionSaveAttempts.count
    #expect(try !catalog.setProject("project-b", selected: false))
    #expect(accountDataStore.projectSelectionSaveAttempts.count == finalSelectionSaveCount)
}

@Test func projectCatalogConfirmsProjectsAtomicallyAndUsesTheFirstVisibleSelection() throws {
    let accountDataStore = InMemoryAccountDataStore()
    var catalog = ProjectCatalog(persistence: accountDataStore)
    try catalog.reconcile(with: [
        VercelProject(id: "project-z", name: "Zebra"),
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-b", name: "Beta"),
    ])
    let savesBeforeConfirmation = accountDataStore.projectSelectionSaveAttempts.count

    #expect(try catalog.confirmSelection(["project-z", "project-b"]))
    #expect(catalog.selectedProjectIDs == ["project-z", "project-b"])
    #expect(catalog.currentProjectID == "project-b")
    #expect(accountDataStore.projectSelectionSaveAttempts.count == savesBeforeConfirmation + 1)

    #expect(try !catalog.confirmSelection([]))
    #expect(try !catalog.confirmSelection(["missing-project"]))
    #expect(accountDataStore.projectSelectionSaveAttempts.count == savesBeforeConfirmation + 1)
}

@MainActor
@Test func appModelKeepsProjectSelectionAtomicWhenPersistenceFails() async {
    let accountDataStore = InMemoryAccountDataStore()
    let projects = [
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-b", name: "Beta"),
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
    accountDataStore.failProjectSelectionSave = true
    #expect(!model.confirmProjectSelection(["project-a", "project-b"]))

    #expect(model.selectedProjectIDs.isEmpty)
    #expect(model.currentProjectID == nil)
    #expect(accountDataStore.selectedProjectIDs.isEmpty)
    #expect(accountDataStore.currentProjectID == nil)
    #expect(model.projectSelectionError == "The project selection could not be saved. Try again.")
}

@MainActor
@Test func appModelDoesNotLoadSnapshotWhenCurrentProjectPersistenceFails() async {
    let accountDataStore = InMemoryAccountDataStore()
    let betaProvider = ControlledSnapshotProvider()
    let projects = [
        VercelProject(id: "project-a", name: "Alpha"),
        VercelProject(id: "project-b", name: "Beta"),
    ]
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: accountDataStore,
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: projects) },
        analyticsProviderFactory: { _, project in
            if project.id == "project-b" {
                betaProvider
            } else {
                FixtureAnalyticsSnapshotProvider()
            }
        },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    #expect(model.confirmProjectSelection(["project-a", "project-b"]))
    accountDataStore.failProjectSelectionSave = true
    await model.selectProject("project-b")

    #expect(model.currentProjectID == "project-a")
    #expect(accountDataStore.currentProjectID == "project-a")
    #expect(await betaProvider.requestedRanges.isEmpty)
    #expect(model.projectSelectionError != nil)
}

@MainActor
@Test func appModelRepairsFailedSelectionRestoreAfterDiscovery() async {
    let accountDataStore = InMemoryAccountDataStore(
        selectedProjectIDs: ["project-invalid"],
        currentProjectID: "project-invalid"
    )
    accountDataStore.failProjectSelectionRead = true
    let project = VercelProject(id: "project-a", name: "Alpha")
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: accountDataStore,
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")

    #expect(model.accountState == .connected)
    #expect(model.projectState == .loaded([project]))
    #expect(model.selectedProjectIDs.isEmpty)
    #expect(accountDataStore.selectedProjectIDs.isEmpty)
    #expect(accountDataStore.currentProjectID == nil)
    #expect(model.projectSelectionError == nil)
}

@MainActor
@Test func appModelShowsEmptyStateWhenNoProjectIsSelected() async {
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: []) },
        analyticsProviderFactory: { _, _ in FixtureAnalyticsSnapshotProvider() },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    await model.load()

    #expect(model.state == .empty("Select a Vercel project to load analytics."))
}
