import Foundation

public struct AnalyticsSnapshot: Codable, Equatable, Sendable {
    public let projectName: String
    public let range: VercelAnalyticsRange
    public let visitors: AnalyticsMetric
    public let pageViews: AnalyticsMetric
    public let series: [VercelAnalyticsPoint]
    public let last24HoursVisitors: Int
    public let refreshedAt: Date

    public init(
        projectName: String,
        range: VercelAnalyticsRange,
        visitors: AnalyticsMetric,
        pageViews: AnalyticsMetric,
        series: [VercelAnalyticsPoint],
        last24HoursVisitors: Int,
        refreshedAt: Date
    ) {
        self.projectName = projectName
        self.range = range
        self.visitors = visitors
        self.pageViews = pageViews
        self.series = series
        self.last24HoursVisitors = last24HoursVisitors
        self.refreshedAt = refreshedAt
    }
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
