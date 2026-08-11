import Foundation

public enum VercelAnalyticsRange: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case last24Hours
    case last7Days
    case last30Days

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

    var dashboardPeriod: String {
        switch self {
        case .last24Hours:
            "24h"
        case .last7Days:
            "7d"
        case .last30Days:
            "30d"
        }
    }

    func plan(at date: Date, timeZone: TimeZone = .current) -> VercelAnalyticsRangePlan {
        let currentWindow = alignedWindow(at: date, timeZone: timeZone)
        let previousWindow = precedingWindow(before: currentWindow)
        return VercelAnalyticsRangePlan(
            currentWindow: currentWindow,
            previousWindow: previousWindow,
            bucket: bucket
        )
    }

    private var bucket: VercelAnalyticsBucket {
        switch self {
        case .last24Hours:
            .hour
        case .last7Days, .last30Days:
            .day
        }
    }

    private func alignedWindow(at date: Date, timeZone: TimeZone) -> VercelAnalyticsInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let currentHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        let endExclusive = calendar.date(byAdding: .hour, value: 1, to: currentHour)
            ?? currentHour.addingTimeInterval(60 * 60)
        let start = switch self {
        case .last24Hours:
            calendar.date(byAdding: .hour, value: -23, to: currentHour)
                ?? currentHour.addingTimeInterval(-23 * 60 * 60)
        case .last7Days:
            calendar.date(byAdding: .day, value: -7, to: currentHour)
                ?? currentHour.addingTimeInterval(-7 * 24 * 60 * 60)
        case .last30Days:
            calendar.date(byAdding: .day, value: -30, to: currentHour)
                ?? currentHour.addingTimeInterval(-30 * 24 * 60 * 60)
        }
        return VercelAnalyticsInterval(start: start, endExclusive: endExclusive)
    }

    private func precedingWindow(before currentWindow: VercelAnalyticsInterval) -> VercelAnalyticsInterval {
        let duration = currentWindow.endExclusive.timeIntervalSince(currentWindow.start)
        return VercelAnalyticsInterval(
            start: currentWindow.start.addingTimeInterval(-duration),
            endExclusive: currentWindow.start
        )
    }
}

struct VercelAnalyticsRangePlan: Equatable, Sendable {
    let currentWindow: VercelAnalyticsInterval
    let previousWindow: VercelAnalyticsInterval
    let bucket: VercelAnalyticsBucket
}

struct VercelAnalyticsInterval: Equatable, Sendable {
    let start: Date
    let endExclusive: Date
}

enum VercelAnalyticsBucket: Equatable, Sendable {
    case hour
    case day
}
