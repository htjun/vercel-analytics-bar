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
        case failed(String)
    }

    enum AccountState: Equatable {
        case disconnected
        case restoring
        case validating
        case connected
        case failed(AccountConnectionError)
    }

    private(set) var state: State = .idle
    private(set) var accountState: AccountState = .disconnected

    private let provider: any AnalyticsSnapshotProviding
    private let credentialStore: any VercelCredentialStore
    private let accountDataStore: any VercelAccountDataStore
    private let tokenValidator: @Sendable (String) async throws -> Void
    private var didAttemptRestore = false

    init(
        provider: any AnalyticsSnapshotProviding,
        credentialStore: any VercelCredentialStore = KeychainVercelCredentialStore(),
        accountDataStore: any VercelAccountDataStore = UserDefaultsVercelAccountDataStore(),
        tokenValidator: @escaping @Sendable (String) async throws -> Void = {
            try await VercelAPIClient(token: $0).validateToken()
        }
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.accountDataStore = accountDataStore
        self.tokenValidator = tokenValidator
    }

    func load() async {
        state = .loading

        do {
            state = .loaded(try await provider.snapshot())
        } catch {
            state = .failed(error.localizedDescription)
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
        } catch {
            accountState = .failed(connectionError(for: error))
        }
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
        } else {
            accountState = .failed(.storageFailure)
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
