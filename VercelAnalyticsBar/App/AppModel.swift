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

    private(set) var state: State = .idle
    private(set) var accountState: AccountState = .disconnected
    private(set) var projectState: ProjectState = .idle
    private(set) var selectedProjectIDs: Set<String> = []
    private(set) var projectSelectionError: String?

    private let provider: (any AnalyticsSnapshotProviding)?
    private let credentialStore: any VercelCredentialStore
    private let accountDataStore: any VercelAccountDataStore
    private let tokenValidator: @Sendable (String) async throws -> Void
    private let projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)?
    private let analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)?
    private var didAttemptRestore = false

    init(
        provider: (any AnalyticsSnapshotProviding)? = nil,
        credentialStore: any VercelCredentialStore = KeychainVercelCredentialStore(),
        accountDataStore: any VercelAccountDataStore = UserDefaultsVercelAccountDataStore(),
        projectProviderFactory: (@Sendable (String) -> any VercelProjectListingProviding)? = nil,
        analyticsProviderFactory: (@Sendable (String, VercelProject) -> any AnalyticsSnapshotProviding)? = nil,
        tokenValidator: @escaping @Sendable (String) async throws -> Void = {
            try await VercelAPIClient(token: $0).validateToken()
        }
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.accountDataStore = accountDataStore
        self.projectProviderFactory = projectProviderFactory
        self.analyticsProviderFactory = analyticsProviderFactory
        self.tokenValidator = tokenValidator
    }

    func load() async {
        if accountState == .connected {
            await loadLiveSnapshot()
            return
        }

        guard let provider else {
            state = .empty("Connect a Vercel account in Settings to load analytics.")
            return
        }
        await loadSnapshot(using: provider)
    }

    private func loadSnapshot(using provider: any AnalyticsSnapshotProviding) async {
        state = .loading

        do {
            let snapshot = try await provider.snapshot()
            state = .loaded(snapshot)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadLiveSnapshot() async {
        guard let analyticsProviderFactory else {
            state = .empty("Live analytics is not configured.")
            return
        }
        guard let project = currentProject else {
            state = .empty("Select a Vercel project in Settings to load analytics.")
            return
        }

        do {
            guard let token = try credentialStore.read() else {
                state = .empty("Connect a Vercel account in Settings to load analytics.")
                return
            }
            await loadSnapshot(using: analyticsProviderFactory(token, project))
        } catch {
            state = .failed("The Vercel account could not be read securely.")
        }
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
            updateSelectedProjectIDs(selectedProjectIDs.union([projectID]))
        } else {
            guard selectedProjectIDs.count > 1 else { return }
            updateSelectedProjectIDs(selectedProjectIDs.subtracting([projectID]))
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

        didAttemptRestore = true
        if failure == nil {
            state = .idle
            accountState = .disconnected
            projectState = .idle
            selectedProjectIDs = []
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

            try accountDataStore.saveSelectedProjectIDs(restoredIDs)
            selectedProjectIDs = restoredIDs
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
            projectSelectionError = nil
        } catch {
            selectedProjectIDs = []
            projectSelectionError = error.localizedDescription
        }
    }

    private func updateSelectedProjectIDs(_ projectIDs: Set<String>) {
        do {
            try accountDataStore.saveSelectedProjectIDs(projectIDs)
            selectedProjectIDs = projectIDs
            projectSelectionError = nil
            state = .idle
        } catch {
            projectSelectionError = error.localizedDescription
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
    var currentProject: VercelProject? {
        guard case let .loaded(projects) = projectState else { return nil }
        return projects.first { selectedProjectIDs.contains($0.id) }
    }

    var abbreviatedVisitors: String? {
        guard case let .loaded(snapshot) = state else { return nil }
        return Self.abbreviated(snapshot.primaryMetric.value)
    }

    private static func abbreviated(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(value / 1_000_000)M"
        }
        if value >= 1000 {
            let whole = value / 1000
            let tenth = (value % 1000) / 100
            return tenth == 0 ? "\(whole)K" : "\(whole).\(tenth)K"
        }
        return value.formatted(.number)
    }
}

enum AccountConnectionError: Equatable, LocalizedError {
    case missingToken
    case invalidToken
    case insufficientPermissions
    case network
    case serviceUnavailable
    case storageFailure
    case unknown

    init(apiError: VercelAPIError) {
        switch apiError {
        case .missingToken:
            self = .missingToken
        case .authentication:
            self = .invalidToken
        case .permissionDenied:
            self = .insufficientPermissions
        case .transient, .rateLimited:
            self = .serviceUnavailable
        case .network:
            self = .network
        case .resourceNotFound, .requestRejected, .malformedResponse:
            self = .unknown
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Enter a Vercel access token to connect."
        case .invalidToken:
            "The Vercel access token is invalid or expired."
        case .insufficientPermissions:
            "The Vercel access token does not have enough permission."
        case .network:
            "The Vercel account could not be reached."
        case .serviceUnavailable:
            "Vercel is temporarily unavailable or rate limited."
        case .storageFailure:
            "The Vercel account could not be stored securely."
        case .unknown:
            "The Vercel account could not be connected."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingToken:
            "Paste a Personal Access Token from Vercel."
        case .invalidToken:
            "Create a new token in Vercel and try again."
        case .insufficientPermissions:
            "Use a token with access to the required Vercel resources."
        case .network:
            "Check your connection and try again."
        case .serviceUnavailable:
            "Wait briefly and try again."
        case .storageFailure, .unknown:
            "Try again or disconnect and reconnect the account."
        }
    }
}
