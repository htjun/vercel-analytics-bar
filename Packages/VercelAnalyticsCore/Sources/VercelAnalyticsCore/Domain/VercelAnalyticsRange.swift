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

    func plan(at date: Date) -> VercelAnalyticsRangePlan {
        let currentWindow = alignedWindow(at: date)
        let previousWindow = precedingWindow(before: currentWindow.start)
        return VercelAnalyticsRangePlan(
            currentWindow: currentWindow,
            previousWindow: previousWindow,
            bucket: bucket,
            totalsSource: totalsSource
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

    private var totalsSource: VercelAnalyticsTotalsSource {
        switch self {
        case .last24Hours:
            .aggregate
        case .last7Days, .last30Days:
            .count
        }
    }

    private var bucketCount: Int {
        switch self {
        case .last24Hours:
            24
        case .last7Days:
            7
        case .last30Days:
            30
        }
    }

    private func alignedWindow(at date: Date) -> VercelAnalyticsInterval {
        let calendar = Self.utcCalendar
        switch bucket {
        case .hour:
            let currentHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
            let start = calendar.date(byAdding: .hour, value: -(bucketCount - 1), to: currentHour)
                ?? date.addingTimeInterval(-TimeInterval(bucketCount * 60 * 60))
            let endExclusive = calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? date
            return VercelAnalyticsInterval(start: start, endExclusive: endExclusive)
        case .day:
            let endExclusive = calendar.startOfDay(for: date)
            let start = calendar.date(byAdding: .day, value: -bucketCount, to: endExclusive)
                ?? date.addingTimeInterval(-TimeInterval(bucketCount * 24 * 60 * 60))
            return VercelAnalyticsInterval(start: start, endExclusive: endExclusive)
        }
    }

    private func precedingWindow(before endExclusive: Date) -> VercelAnalyticsInterval {
        let calendar = Self.utcCalendar
        let start = calendar.date(byAdding: bucket.calendarComponent, value: -bucketCount, to: endExclusive)
            ?? endExclusive.addingTimeInterval(-TimeInterval(bucketCount) * bucket.duration)
        return VercelAnalyticsInterval(start: start, endExclusive: endExclusive)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

struct VercelAnalyticsRangePlan: Equatable, Sendable {
    let currentWindow: VercelAnalyticsInterval
    let previousWindow: VercelAnalyticsInterval
    let bucket: VercelAnalyticsBucket
    let totalsSource: VercelAnalyticsTotalsSource
}

struct VercelAnalyticsInterval: Equatable, Sendable {
    let start: Date
    let endExclusive: Date
}

enum VercelAnalyticsBucket: Equatable, Sendable {
    case hour
    case day

    var calendarComponent: Calendar.Component {
        switch self {
        case .hour:
            .hour
        case .day:
            .day
        }
    }

    var duration: TimeInterval {
        switch self {
        case .hour:
            60 * 60
        case .day:
            24 * 60 * 60
        }
    }
}

enum VercelAnalyticsTotalsSource: Equatable, Sendable {
    case aggregate
    case count
}
