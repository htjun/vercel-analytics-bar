import Foundation

public struct VercelAccountProfile: Equatable, Sendable {
    public let id: String?
    public let name: String?
    public let username: String?
    public let avatarURL: URL?

    public init(
        id: String? = nil,
        name: String? = nil,
        username: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.avatarURL = avatarURL
    }

    public var displayName: String {
        Self.nonEmpty(name) ?? Self.nonEmpty(username) ?? "Vercel account"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

public struct VercelAccountDiscovery: Equatable, Sendable {
    public let profile: VercelAccountProfile?
    public let projects: [VercelProject]

    public init(profile: VercelAccountProfile?, projects: [VercelProject]) {
        self.profile = profile
        self.projects = projects
    }
}

public struct VercelProject: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let updatedAt: Date?
    public let teamID: String?
    public let teamName: String?
    public let scopeSlug: String?

    public init(
        id: String,
        name: String,
        updatedAt: Date? = nil,
        teamID: String? = nil,
        teamName: String? = nil,
        scopeSlug: String? = nil
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.teamID = teamID
        self.teamName = teamName
        self.scopeSlug = scopeSlug
    }
}

public extension VercelProject {
    static func sorted(_ projects: [VercelProject]) -> [VercelProject] {
        projects.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            let teamOrder = (lhs.teamName ?? "").localizedCaseInsensitiveCompare(rhs.teamName ?? "")
            if teamOrder != .orderedSame {
                return teamOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    func analyticsDashboardURL(for range: VercelAnalyticsRange) -> URL? {
        guard let scopeSlug, !scopeSlug.isEmpty, !name.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "vercel.com"
        components.path = "/\(scopeSlug)/\(name)/analytics"
        components.queryItems = [URLQueryItem(name: "period", value: range.dashboardPeriod)]
        return components.url
    }
}

public enum VercelAnalyticsDimension: String, Equatable, Sendable {
    case requestPath
    case referrerHostname
}

public struct VercelAnalyticsWindow: Equatable, Sendable {
    public let since: Date
    public let until: Date

    public init(since: Date, until: Date) {
        self.since = since
        self.until = until
    }
}

public struct VercelAnalyticsCount: Equatable, Sendable {
    public let visitors: Int
    public let pageViews: Int
    public let window: VercelAnalyticsWindow

    public init(visitors: Int, pageViews: Int, window: VercelAnalyticsWindow) {
        self.visitors = visitors
        self.pageViews = pageViews
        self.window = window
    }
}

public struct VercelAnalyticsPoint: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let visitors: Int
    public let pageViews: Int

    public init(timestamp: Date, visitors: Int, pageViews: Int) {
        self.timestamp = timestamp
        self.visitors = visitors
        self.pageViews = pageViews
    }
}

public struct VercelAnalyticsSeries: Equatable, Sendable {
    public let points: [VercelAnalyticsPoint]
    public let window: VercelAnalyticsWindow

    public init(points: [VercelAnalyticsPoint], window: VercelAnalyticsWindow) {
        self.points = points
        self.window = window
    }
}
