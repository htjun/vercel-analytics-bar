import Foundation

public struct AnalyticsSnapshot: Codable, Equatable, Sendable {
    public let projectName: String
    public let range: VercelAnalyticsRange
    public let visitors: AnalyticsMetric
    public let pageViews: AnalyticsMetric
    public let series: [VercelAnalyticsPoint]
    public let topPages: [VercelAnalyticsBreakdown]
    public let topReferrers: [VercelAnalyticsBreakdown]
    public let last24HoursVisitors: Int
    public let refreshedAt: Date

    public init(
        projectName: String,
        range: VercelAnalyticsRange,
        visitors: AnalyticsMetric,
        pageViews: AnalyticsMetric,
        series: [VercelAnalyticsPoint],
        topPages: [VercelAnalyticsBreakdown] = [],
        topReferrers: [VercelAnalyticsBreakdown] = [],
        last24HoursVisitors: Int,
        refreshedAt: Date
    ) {
        self.projectName = projectName
        self.range = range
        self.visitors = visitors
        self.pageViews = pageViews
        self.series = series
        self.topPages = topPages
        self.topReferrers = topReferrers
        self.last24HoursVisitors = last24HoursVisitors
        self.refreshedAt = refreshedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try container.decode(String.self, forKey: .projectName)
        range = try container.decode(VercelAnalyticsRange.self, forKey: .range)
        visitors = try container.decode(AnalyticsMetric.self, forKey: .visitors)
        pageViews = try container.decode(AnalyticsMetric.self, forKey: .pageViews)
        series = try container.decode([VercelAnalyticsPoint].self, forKey: .series)
        topPages = try container.decodeIfPresent([VercelAnalyticsBreakdown].self, forKey: .topPages) ?? []
        topReferrers = try container.decodeIfPresent([VercelAnalyticsBreakdown].self, forKey: .topReferrers) ?? []
        last24HoursVisitors = try container.decode(Int.self, forKey: .last24HoursVisitors)
        refreshedAt = try container.decode(Date.self, forKey: .refreshedAt)
    }
}

public struct VercelAnalyticsBreakdown: Codable, Equatable, Identifiable, Sendable {
    public let label: String
    public let visitors: Int
    public let pageViews: Int

    public init(label: String, visitors: Int, pageViews: Int) {
        self.label = label
        self.visitors = visitors
        self.pageViews = pageViews
    }

    public var id: String { label }
}

public struct AnalyticsMetric: Codable, Equatable, Sendable {
    public let label: String
    public let value: Int
    public let previousValue: Int

    public init(label: String, value: Int, previousValue: Int) {
        self.label = label
        self.value = value
        self.previousValue = previousValue
    }

    public var comparison: AnalyticsComparison {
        guard previousValue != 0 else {
            return value == 0 ? .percentage(0) : .new
        }

        let difference = Double(value - previousValue)
        return .percentage(difference / Double(previousValue) * 100)
    }
}

public enum AnalyticsComparison: Equatable, Sendable {
    case percentage(Double)
    case new
}
