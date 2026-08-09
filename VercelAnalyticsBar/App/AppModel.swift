import Foundation
import Observation
import VercelAnalyticsCore

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(AnalyticsSnapshot)
        case empty(String)
        case failed(String)
    }

    enum AccountState: Equatable {
        case disconnected
        case restoring
        case validating
        case connected
        case failed(AccountConnectionError)
    }

    enum ProjectState: Equatable {
        case idle
        case loading
        case loaded([VercelProject])
        case failed(String)
    }

    var state: State = .idle
    private(set) var accountState: AccountState = .disconnected
    private(set) var projectState: ProjectState = .idle
    private(set) var projectCatalog: ProjectCatalog
    private(set) var selectedRange: VercelAnalyticsRange
    private(set) var projectSelectionError: String?
    var snapshotFreshness: SnapshotFreshness = .fresh
    var refreshMessage: String?
    var retryAvailableAt: Date?

    let provider: (any AnalyticsSnapshotProviding)?
    let credentialStore: any VercelCredentialStore
    let accountDataStore: any VercelAccountDataStore
    let snapshotRefreshCoordinator: SnapshotRefreshCoordinator
    private let tokenValidator: @Sendable (String) async throws -> Void
    let projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)?
    let analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)?
    let launchAtLoginManager: any LaunchAtLoginManaging
    let sleep: @Sendable (Duration) async throws -> Void
    var refreshLoopTask: Task<Void, Never>?
    private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    private(set) var launchAtLoginError: String?
    private var didAttemptRestore = false

    var selectedProjectIDs: Set<String> {
        projectCatalog.selectedProjectIDs
    }

    var currentProjectID: String? {
        projectCatalog.currentProjectID
    }

    init(
        provider: (any AnalyticsSnapshotProviding)? = nil,
        credentialStore: any VercelCredentialStore = KeychainVercelCredentialStore(),
        accountDataStore: any VercelAccountDataStore = UserDefaultsVercelAccountDataStore(),
        snapshotCacheStore: any AnalyticsSnapshotCacheStore = FileAnalyticsSnapshotCacheStore(),
        projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)? = nil,
        analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)? = nil,
        launchAtLoginManager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        tokenValidator: @escaping @Sendable (String) async throws -> Void = {
            try await VercelAPIClient(token: $0).validateToken()
        }
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.accountDataStore = accountDataStore
        snapshotRefreshCoordinator = SnapshotRefreshCoordinator(
            cacheStore: snapshotCacheStore,
            now: now
        )
        self.projectProviderFactory = projectProviderFactory
        self.analyticsProviderFactory = analyticsProviderFactory
        self.launchAtLoginManager = launchAtLoginManager
        self.sleep = sleep
        self.tokenValidator = tokenValidator
        projectCatalog = ProjectCatalog(
            selection: (try? accountDataStore.readProjectSelection()) ?? .empty
        )
        selectedRange = (try? accountDataStore.readAnalyticsRange()) ?? .last7Days
        launchAtLoginStatus = launchAtLoginManager.status
    }

    func restoreConnection() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        accountState = .restoring

        do {
            guard let token = try credentialStore.read() else {
                accountState = .disconnected
                return
            }

            try await tokenValidator(token)
            accountState = .connected
            restoreSelectedProjects()
            await refreshProjects(token: token)
        } catch {
            accountState = .failed(connectionError(for: error))
        }
    }

    func connect(token: String) async {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            accountState = .failed(.missingToken)
            return
        }

        accountState = .validating

        do {
            try await tokenValidator(normalizedToken)
            try credentialStore.save(normalizedToken)
            didAttemptRestore = true
            accountState = .connected
            restoreSelectedProjects()
            await refreshProjects(token: normalizedToken)
        } catch {
            accountState = .failed(connectionError(for: error))
        }
    }

    private func connectionError(for error: any Error) -> AccountConnectionError {
        if let error = error as? VercelAPIError {
            return AccountConnectionError(apiError: error)
        }
        if error is CredentialStoreError {
            return .storageFailure
        }
        return .unknown
    }
}

extension AppModel {
    func refreshProjects() async {
        do {
            guard let token = try credentialStore.read() else {
                projectState = .failed("Connect a Vercel account before syncing projects.")
                return
            }
            await refreshProjects(token: token)
        } catch {
            projectState = .failed("The Vercel project list could not be loaded.")
        }
    }

    func syncNow() async {
        await refreshProjects()
        guard case .loaded = projectState else { return }
        await load(trigger: .manual)
    }

    func setLaunchAtLogin(enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginStatus = launchAtLoginManager.status
            launchAtLoginError = nil
        } catch {
            launchAtLoginStatus = launchAtLoginManager.status
            launchAtLoginError = error.localizedDescription
        }
    }

    func setProjectSelected(_ projectID: String, selected: Bool) {
        guard case .loaded = projectState else { return }

        var updatedCatalog = projectCatalog
        guard updatedCatalog.setProject(projectID, selected: selected) else { return }

        do {
            try accountDataStore.saveProjectSelection(updatedCatalog.selection)
            projectCatalog = updatedCatalog
            projectSelectionError = nil
            state = .idle
        } catch {
            projectSelectionError = error.localizedDescription
        }
    }

    func selectProject(_ projectID: String) async {
        guard case .loaded = projectState else { return }

        var updatedCatalog = projectCatalog
        guard updatedCatalog.selectCurrentProject(projectID) else { return }

        do {
            try accountDataStore.saveProjectSelection(updatedCatalog.selection)
            projectCatalog = updatedCatalog
            projectSelectionError = nil
        } catch {
            projectSelectionError = error.localizedDescription
            return
        }

        await loadLiveSnapshot(trigger: .projectSwitch)
    }

    func selectAnalyticsRange(_ range: VercelAnalyticsRange) async {
        guard range != selectedRange else { return }

        do {
            try accountDataStore.saveAnalyticsRange(range)
            selectedRange = range
            state = .idle
            await load(trigger: .rangeChanged)
        } catch {
            state = .failed("The analytics range could not be saved.")
        }
    }

    func projects(matching searchQuery: String) -> [VercelProject] {
        guard case .loaded = projectState else { return [] }
        return projectCatalog.projects(matching: searchQuery)
    }

    func teamMetadata(for project: VercelProject) -> String? {
        guard case .loaded = projectState else { return nil }
        return projectCatalog.teamMetadata(for: project)
    }

    func disconnect() {
        var failure: (any Error)?

        do {
            try credentialStore.delete()
        } catch {
            failure = error
        }

        do {
            try accountDataStore.clear()
        } catch {
            failure = failure ?? error
        }

        do {
            try snapshotRefreshCoordinator.clearCache()
        } catch {
            failure = failure ?? error
        }

        snapshotRefreshCoordinator.reset()
        didAttemptRestore = true
        if failure == nil {
            state = .idle
            accountState = .disconnected
            projectState = .idle
            projectCatalog = ProjectCatalog()
            snapshotFreshness = .fresh
            refreshMessage = nil
            retryAvailableAt = nil
            selectedRange = .last7Days
            projectSelectionError = nil
        } else {
            accountState = .failed(.storageFailure)
        }
    }

    private func refreshProjects(token: String) async {
        guard let projectProviderFactory else { return }

        projectState = .loading

        do {
            let projects = try await projectProviderFactory(token).listAccessibleProjects()
            var updatedCatalog = projectCatalog
            updatedCatalog.reconcile(with: projects)
            try accountDataStore.saveProjectSelection(updatedCatalog.selection)
            projectCatalog = updatedCatalog
            projectSelectionError = nil
            state = .idle
            projectState = .loaded(updatedCatalog.projects)
        } catch {
            projectState = .failed(error.localizedDescription)
        }
    }

    private func restoreSelectedProjects() {
        do {
            let selection = try accountDataStore.readProjectSelection()
            projectCatalog.restore(selection)
            projectSelectionError = nil
        } catch {
            projectCatalog.restore(.empty)
            projectSelectionError = error.localizedDescription
        }
    }
}
