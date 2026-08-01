import Foundation

public struct AnalyticsSnapshot: Equatable, Sendable {
    public let projectName: String
    public let primaryMetric: AnalyticsMetric
    public let refreshedAt: Date

    public init(
        projectName: String,
        primaryMetric: AnalyticsMetric,
        refreshedAt: Date
    ) {
        self.projectName = projectName
        self.primaryMetric = primaryMetric
        self.refreshedAt = refreshedAt
    }
}

public struct AnalyticsMetric: Equatable, Sendable {
    public let label: String
    public let value: Int

    public init(label: String, value: Int) {
        self.label = label
        self.value = value
    }
}
