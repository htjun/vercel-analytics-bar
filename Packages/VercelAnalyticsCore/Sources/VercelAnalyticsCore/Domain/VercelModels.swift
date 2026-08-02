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

    public init(id: String, name: String, teamID: String? = nil) {
        self.id = id
        self.name = name
        self.teamID = teamID
    }
}

public enum VercelAnalyticsRange: String, CaseIterable, Equatable, Sendable {
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

public struct VercelAnalyticsPoint: Equatable, Sendable {
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
