import Foundation
import VercelAnalyticsCore

enum AnalyticsCountFormatter {
    static func compact(_ value: Int) -> String {
        if value < 1000 {
            return value.formatted(.number.grouping(.never))
        }
        if value < 999_500 {
            return compact(value, divisor: 1000, suffix: "K")
        }
        if value < 999_500_000 {
            return compact(value, divisor: 1_000_000, suffix: "M")
        }
        return "999M+"
    }

    private static func compact(_ value: Int, divisor: Int, suffix: String) -> String {
        let roundingIncrement = value < divisor * 10 ? divisor / 10 : divisor
        let roundedValue = (value + roundingIncrement / 2) / roundingIncrement * roundingIncrement
        let whole = roundedValue / divisor

        guard roundedValue < divisor * 10 else {
            return "\(whole)\(suffix)"
        }

        let tenth = roundedValue % divisor / (divisor / 10)
        return tenth == 0 ? "\(whole)\(suffix)" : "\(whole).\(tenth)\(suffix)"
    }
}

extension AppModel {
    var currentProject: VercelProject? {
        guard case .loaded = projectState else { return nil }
        return projectCatalog.currentProject
    }

    func selectedProjects(matching searchQuery: String) -> [VercelProject] {
        guard case .loaded = projectState else { return [] }
        return projectCatalog.selectedProjects(matching: searchQuery)
    }

    var abbreviatedVisitors: String? {
        guard case let .loaded(snapshot) = state else { return nil }
        return AnalyticsCountFormatter.compact(snapshot.last24HoursVisitors)
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
