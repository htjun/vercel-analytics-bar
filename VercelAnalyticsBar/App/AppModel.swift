import Foundation
import Observation
import OSLog
import VercelAnalyticsCore

@MainActor
@Observable
final class AppModel {
    typealias State = AnalyticsPresentationState

    private static let credentialLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jasonjun.VercelAnalyticsBar",
        category: "CredentialStore"
    )

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

    var state: State {
        snapshotRefreshCoordinator.state.content
    }

    var snapshotFreshness: SnapshotFreshness {
        snapshotRefreshCoordinator.state.freshness
    }

    var refreshMessage: String? {
        snapshotRefreshCoordinator.state.message
    }

    var retryAvailableAt: Date? {
        snapshotRefreshCoordinator.state.retryAvailableAt
    }

    private(set) var accountState: AccountState = .disconnected
    private(set) var connectedAccount: VercelAccountProfile?
    private(set) var projectState: ProjectState = .idle
    private(set) var isRefreshingProjects = false
    private(set) var projectRefreshError: String?
    private(set) var projectCatalog: ProjectCatalog
    private(set) var selectedRange: VercelAnalyticsRange
    private(set) var projectSelectionError: String?
    let provider: (any AnalyticsSnapshotProviding)?
    let credentialStore: any VercelCredentialStore
    let accountDataStore: any VercelAccountDataStore
    let snapshotRefreshCoordinator: SnapshotRefreshCoordinator
    private let tokenValidator: @Sendable (String) async throws -> Void
    let projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)?
    let analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)?
    let launchAtLoginManager: any LaunchAtLoginManaging
    private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    private(set) var launchAtLoginError: String?
    private var didAttemptRestore = false
    private(set) var activeToken: String?

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
            now: now,
            sleep: sleep
        )
        self.projectProviderFactory = projectProviderFactory
        self.analyticsProviderFactory = analyticsProviderFactory
        self.launchAtLoginManager = launchAtLoginManager
        self.tokenValidator = tokenValidator
        projectCatalog = ProjectCatalog(persistence: accountDataStore)
        selectedRange = (try? accountDataStore.readAnalyticsRange()) ?? .last7Days
        launchAtLoginStatus = launchAtLoginManager.status
    }

    func restoreConnection() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        activeToken = nil
        connectedAccount = nil
        accountState = .restoring

        do {
            guard let token = try credentialStore.read() else {
                accountState = .disconnected
                return
            }

            try await tokenValidator(token)
            activeToken = token
            accountState = .connected
            restoreProjectCatalog()
            await refreshProjects(token: token)
        } catch {
            activeToken = nil
            connectedAccount = nil
            accountState = .failed(connectionError(for: error))
        }
    }

    func connect(token: String) async {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            activeToken = nil
            connectedAccount = nil
            accountState = .failed(.missingToken)
            return
        }

        activeToken = nil
        connectedAccount = nil
        accountState = .validating

        do {
            try await tokenValidator(normalizedToken)
            try credentialStore.save(normalizedToken)
            try accountDataStore.saveAnalyticsRange(.last24Hours)
            selectedRange = .last24Hours
            activeToken = normalizedToken
            didAttemptRestore = true
            accountState = .connected
            restoreProjectCatalog()
            await refreshProjects(token: normalizedToken)
        } catch {
            activeToken = nil
            connectedAccount = nil
            accountState = .failed(connectionError(for: error))
        }
    }

    private func connectionError(for error: any Error) -> AccountConnectionError {
        if let error = error as? VercelAPIError {
            return AccountConnectionError(apiError: error)
        }
        if let credentialError = error as? CredentialStoreError {
            Self.logCredentialStoreError(credentialError)
            return .storageFailure
        }
        return .unknown
    }

    private static func logCredentialStoreError(_ error: CredentialStoreError) {
        credentialLogger.error("\(error.diagnosticDescription, privacy: .public)")
    }
}

extension AppModel {
    func refreshProjects() async {
        guard let activeToken else {
            let message = "Connect a Vercel account before refreshing projects."
            projectRefreshError = message
            if case .loaded = projectState {
                return
            }
            projectState = .failed(message)
            return
        }
        await refreshProjects(token: activeToken, preservesLoadedProjects: true)
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

    func clearProjectRefreshError() {
        projectRefreshError = nil
    }

    func clearLaunchAtLoginError() {
        launchAtLoginError = nil
    }

    func setProjectSelected(_ projectID: String, selected: Bool) {
        guard case .loaded = projectState else { return }

        do {
            guard try projectCatalog.setProject(projectID, selected: selected) else { return }
            projectSelectionError = nil
            snapshotRefreshCoordinator.present(.idle)
        } catch {
            projectSelectionError = error.localizedDescription
        }
    }

    @discardableResult
    func confirmProjectSelection(_ projectIDs: Set<String>) -> Bool {
        guard case .loaded = projectState, !projectIDs.isEmpty else { return false }

        do {
            guard try projectCatalog.confirmSelection(projectIDs) else { return false }
            projectSelectionError = nil
            snapshotRefreshCoordinator.present(.idle)
            return true
        } catch {
            projectSelectionError = "The project selection could not be saved. Try again."
            return false
        }
    }

    func selectProject(_ projectID: String) async {
        guard case .loaded = projectState else { return }

        do {
            guard try projectCatalog.selectCurrentProject(projectID) else { return }
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
            snapshotRefreshCoordinator.present(.idle)
            await load(trigger: .rangeChanged)
        } catch {
            snapshotRefreshCoordinator.present(.failed("The analytics range could not be saved."))
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
        activeToken = nil
        connectedAccount = nil
        isRefreshingProjects = false
        projectRefreshError = nil

        do {
            try credentialStore.delete()
        } catch {
            if let credentialError = error as? CredentialStoreError {
                Self.logCredentialStoreError(credentialError)
            }
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
            snapshotRefreshCoordinator.present(.idle)
            accountState = .disconnected
            projectState = .idle
            projectCatalog.reset()
            selectedRange = .last7Days
            projectSelectionError = nil
            launchAtLoginError = nil
        } else {
            accountState = .failed(.storageFailure)
        }
    }

    private func refreshProjects(token: String, preservesLoadedProjects: Bool = false) async {
        guard let projectProviderFactory else { return }

        projectRefreshError = nil
        let retainedProjectState: ProjectState? = if preservesLoadedProjects, case .loaded = projectState {
            projectState
        } else {
            nil
        }
        if retainedProjectState == nil {
            projectState = .loading
        }
        isRefreshingProjects = true
        defer { isRefreshingProjects = false }

        do {
            let discovery = try await projectProviderFactory(token).discoverAccount()
            try projectCatalog.reconcile(with: discovery.projects)
            connectedAccount = discovery.profile
            projectSelectionError = nil
            projectRefreshError = nil
            projectState = .loaded(projectCatalog.projects)
        } catch {
            projectRefreshError = error.localizedDescription
            projectState = retainedProjectState ?? .failed(error.localizedDescription)
        }
    }

    private func restoreProjectCatalog() {
        do {
            try projectCatalog.restore()
            projectSelectionError = nil
        } catch {
            projectSelectionError = error.localizedDescription
        }
    }
}
