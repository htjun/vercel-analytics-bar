import Foundation
import VercelAnalyticsCore

struct SnapshotCacheKey: Hashable {
    let projectID: String
    let range: VercelAnalyticsRange
}

struct RefreshRequestKey: Hashable {
    let projectID: String?
    let range: VercelAnalyticsRange
}

enum SnapshotFreshness: Equatable {
    case fresh
    case stale
}

extension AppModel {
    static func cacheDictionary(from entries: [SnapshotCacheEntry]) -> [SnapshotCacheKey: AnalyticsSnapshot] {
        entries.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.snapshot
        }
    }

    var currentProject: VercelProject? {
        guard case let .loaded(projects) = projectState else { return nil }
        if let currentProjectID {
            let currentProject = projects.first(where: { $0.id == currentProjectID })
            if selectedProjectIDs.contains(currentProjectID), let currentProject {
                return currentProject
            }
        }
        return projects.first { selectedProjectIDs.contains($0.id) }
    }

    func selectedProjects(matching searchQuery: String) -> [VercelProject] {
        guard case let .loaded(projects) = projectState else { return [] }

        let selectedProjects = projects.filter { selectedProjectIDs.contains($0.id) }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selectedProjects }
        return selectedProjects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var abbreviatedVisitors: String? {
        guard case let .loaded(snapshot) = state else { return nil }
        return Self.abbreviated(snapshot.last24HoursVisitors)
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
