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
    private(set) var selectedProjectIDs: Set<String> = []
    private(set) var currentProjectID: String?
    private(set) var selectedRange: VercelAnalyticsRange
    private(set) var projectSelectionError: String?
    var snapshotFreshness: SnapshotFreshness = .fresh
    var refreshMessage: String?
    var retryAvailableAt: Date?

    let provider: (any AnalyticsSnapshotProviding)?
    let credentialStore: any VercelCredentialStore
    let accountDataStore: any VercelAccountDataStore
    let snapshotCacheStore: any AnalyticsSnapshotCacheStore
    private let tokenValidator: @Sendable (String) async throws -> Void
    let projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)?
    let analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)?
    let now: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void
    var snapshotCache: [SnapshotCacheKey: AnalyticsSnapshot] = [:]
    var activeRefreshID: UUID?
    var activeRefreshKey: RefreshRequestKey?
    var activeRefreshTask: Task<Void, Never>?
    var refreshLoopTask: Task<Void, Never>?
    var manualRetryCount = 0
    var manualRetryWindowEndsAt: Date?
    var nextRefreshAllowedAt: Date?
    private var didAttemptRestore = false

    init(
        provider: (any AnalyticsSnapshotProviding)? = nil,
        credentialStore: any VercelCredentialStore = KeychainVercelCredentialStore(),
        accountDataStore: any VercelAccountDataStore = UserDefaultsVercelAccountDataStore(),
        snapshotCacheStore: any AnalyticsSnapshotCacheStore = FileAnalyticsSnapshotCacheStore(),
        projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)? = nil,
        analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)? = nil,
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
        self.snapshotCacheStore = snapshotCacheStore
        self.projectProviderFactory = projectProviderFactory
        self.analyticsProviderFactory = analyticsProviderFactory
        self.now = now
        self.sleep = sleep
        self.tokenValidator = tokenValidator
        currentProjectID = try? accountDataStore.readCurrentProjectID()
        selectedRange = (try? accountDataStore.readAnalyticsRange()) ?? .last7Days
        snapshotCache = Self.cacheDictionary(from: (try? snapshotCacheStore.read()) ?? [])
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

    func setProjectSelected(_ projectID: String, selected: Bool) {
        guard case let .loaded(projects) = projectState,
              projects.contains(where: { $0.id == projectID })
        else {
            return
        }

        if selected {
            updateProjectSelection(
                selectedProjectIDs.union([projectID]),
                currentProjectID: currentProjectID ?? projectID
            )
        } else {
            guard selectedProjectIDs.count > 1 else { return }
            let nextSelectedProjectIDs = selectedProjectIDs.subtracting([projectID])
            let nextCurrentProjectID = currentProjectID == projectID
                ? nextSelectedProjectIDs.sorted().first
                : currentProjectID
            updateProjectSelection(
                nextSelectedProjectIDs,
                currentProjectID: nextCurrentProjectID
            )
        }
    }

    func selectProject(_ projectID: String) async {
        guard case let .loaded(projects) = projectState,
              selectedProjectIDs.contains(projectID),
              projects.contains(where: { $0.id == projectID })
        else {
            return
        }

        guard projectID != currentProjectID else { return }

        do {
            try accountDataStore.saveCurrentProjectID(projectID)
            currentProjectID = projectID
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
        guard case let .loaded(projects) = projectState else { return [] }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || (project.teamName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func teamMetadata(for project: VercelProject) -> String? {
        guard case let .loaded(projects) = projectState else { return nil }
        let matchingProjects = projects.filter { $0.name == project.name }
        guard matchingProjects.count > 1 else { return nil }
        return project.teamName ?? "Personal account"
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
            try snapshotCacheStore.clear()
        } catch {
            failure = failure ?? error
        }

        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        activeRefreshID = nil
        didAttemptRestore = true
        if failure == nil {
            state = .idle
            accountState = .disconnected
            projectState = .idle
            selectedProjectIDs = []
            currentProjectID = nil
            snapshotCache.removeAll()
            snapshotFreshness = .fresh
            refreshMessage = nil
            retryAvailableAt = nil
            nextRefreshAllowedAt = nil
            manualRetryCount = 0
            manualRetryWindowEndsAt = nil
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
            let sortedProjects = VercelProject.sorted(projects)
            let availableProjectIDs = Set(sortedProjects.map(\.id))
            var restoredIDs = selectedProjectIDs.intersection(availableProjectIDs)

            if restoredIDs.isEmpty, let firstProject = sortedProjects.first {
                restoredIDs = [firstProject.id]
            }

            let nextCurrentProjectID = if let currentProjectID, restoredIDs.contains(currentProjectID) {
                currentProjectID
            } else {
                restoredIDs.sorted().first
            }
            try accountDataStore.saveCurrentProjectID(nextCurrentProjectID)
            try accountDataStore.saveSelectedProjectIDs(restoredIDs)
            selectedProjectIDs = restoredIDs
            currentProjectID = nextCurrentProjectID
            projectSelectionError = nil
            state = .idle
            projectState = .loaded(sortedProjects)
        } catch {
            projectState = .failed(error.localizedDescription)
        }
    }

    private func restoreSelectedProjects() {
        do {
            selectedProjectIDs = try accountDataStore.readSelectedProjectIDs()
            currentProjectID = try accountDataStore.readCurrentProjectID()
            projectSelectionError = nil
        } catch {
            selectedProjectIDs = []
            currentProjectID = nil
            projectSelectionError = error.localizedDescription
        }
    }

    private func updateProjectSelection(_ projectIDs: Set<String>, currentProjectID: String?) {
        do {
            try accountDataStore.saveSelectedProjectIDs(projectIDs)
            try accountDataStore.saveCurrentProjectID(currentProjectID)
            selectedProjectIDs = projectIDs
            self.currentProjectID = currentProjectID
            projectSelectionError = nil
            state = .idle
        } catch {
            projectSelectionError = error.localizedDescription
        }
    }
}
