import Foundation
import VercelAnalyticsCore

enum AnalyticsCountFormatter {
    private struct Scale {
        let divisor: Int
        let suffix: String
    }

    private static let scales = [
        Scale(divisor: 1000, suffix: "K"),
        Scale(divisor: 1_000_000, suffix: "M"),
        Scale(divisor: 1_000_000_000, suffix: "B"),
        Scale(divisor: 1_000_000_000_000, suffix: "T"),
        Scale(divisor: 1_000_000_000_000_000, suffix: "P"),
        Scale(divisor: 1_000_000_000_000_000_000, suffix: "E"),
    ]

    static func compact(_ value: Int) -> String {
        guard value >= 1000 else {
            return value.formatted(.number.grouping(.never))
        }

        let scale = selectedScale(for: value)
        let roundingIncrement = value / scale.divisor < 10
            ? scale.divisor / 10
            : scale.divisor
        let roundedUnits = roundedUnits(value, increment: roundingIncrement)

        if roundingIncrement == scale.divisor {
            return "\(roundedUnits)\(scale.suffix)"
        }

        let whole = roundedUnits / 10
        let tenth = roundedUnits % 10
        return tenth == 0 ? "\(whole)\(scale.suffix)" : "\(whole).\(tenth)\(scale.suffix)"
    }

    private static func selectedScale(for value: Int) -> Scale {
        for (index, scale) in scales.enumerated() where index < scales.count - 1 {
            let nextScale = scales[index + 1]
            let threshold = nextScale.divisor - nextScale.divisor / 2000
            if value < threshold {
                return scale
            }
        }

        return scales[scales.count - 1]
    }

    private static func roundedUnits(_ value: Int, increment: Int) -> Int {
        let quotient = value / increment
        let remainder = value % increment

        return remainder >= increment / 2 ? quotient + 1 : quotient
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
