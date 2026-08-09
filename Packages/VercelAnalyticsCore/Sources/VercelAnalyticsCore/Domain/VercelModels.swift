import Foundation

public struct VercelTeam: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let slug: String?

    public init(id: String, name: String, slug: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct VercelProject: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let teamID: String?
    public let teamName: String?
    public let scopeSlug: String?
    public let analyticsAvailability: VercelAnalyticsAvailability

    public init(
        id: String,
        name: String,
        teamID: String? = nil,
        teamName: String? = nil,
        scopeSlug: String? = nil,
        analyticsAvailability: VercelAnalyticsAvailability = .unknown
    ) {
        self.id = id
        self.name = name
        self.teamID = teamID
        self.teamName = teamName
        self.scopeSlug = scopeSlug
        self.analyticsAvailability = analyticsAvailability
    }
}

public extension VercelProject {
    static func sorted(_ projects: [VercelProject]) -> [VercelProject] {
        projects.sorted { lhs, rhs in
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

public enum VercelAnalyticsAvailability: String, Equatable, Sendable {
    case available
    case unavailable
    case unknown

    public var label: String {
        switch self {
        case .available:
            "Available"
        case .unavailable:
            "Unavailable"
        case .unknown:
            "Unknown"
        }
    }
}

public enum VercelAnalyticsDimension: String, Equatable, Sendable {
    case requestPath
    case referrerHostname
}

public enum VercelAnalyticsRange: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case last24Hours
    case last7Days
    case last30Days

    public var aggregateBy: String {
        switch self {
        case .last24Hours:
            "hour"
        case .last7Days, .last30Days:
            "day"
        }
    }

    public var title: String {
        switch self {
        case .last24Hours:
            "Last 24 Hours"
        case .last7Days:
            "Last 7 Days"
        case .last30Days:
            "Last 30 Days"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .last24Hours:
            24 * 60 * 60
        case .last7Days:
            7 * 24 * 60 * 60
        case .last30Days:
            30 * 24 * 60 * 60
        }
    }

    fileprivate var dashboardPeriod: String {
        switch self {
        case .last24Hours:
            "24h"
        case .last7Days:
            "7d"
        case .last30Days:
            "30d"
        }
    }
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
