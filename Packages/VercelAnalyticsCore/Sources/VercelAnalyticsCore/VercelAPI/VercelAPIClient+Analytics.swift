import Foundation

private struct AnalyticsQueryWindow: Sendable {
    let start: Date
    let endExclusive: Date

    var countWindow: VercelAnalyticsWindow {
        VercelAnalyticsWindow(since: start, until: endExclusive)
    }

    var aggregateWindow: VercelAnalyticsWindow {
        VercelAnalyticsWindow(since: start, until: endExclusive.addingTimeInterval(-0.001))
    }
}

public extension VercelAPIClient {
    func fetchCount(
        for project: VercelProject,
        range: VercelAnalyticsRange,
        now: Date
    ) async throws -> VercelAnalyticsCount {
        let queryWindow = queryWindow(for: range, now: now)
        let response = try await request(
            AnalyticsCountResponseDTO.self,
            path: "/v1/query/web-analytics/visits/count",
            query: analyticsQuery(for: project, window: queryWindow.countWindow)
        )

        return VercelAnalyticsCount(
            visitors: response.data.visitors,
            pageViews: response.data.pageViews,
            window: response.query.window
        )
    }

    func fetchSeries(
        for project: VercelProject,
        range: VercelAnalyticsRange,
        now: Date
    ) async throws -> VercelAnalyticsSeries {
        let queryWindow = queryWindow(for: range, now: now)
        var query = analyticsQuery(for: project, window: queryWindow.aggregateWindow)
        query["by"] = range.aggregateBy

        let response = try await request(
            AnalyticsSeriesResponseDTO.self,
            path: "/v1/query/web-analytics/visits/aggregate",
            query: query
        )

        return VercelAnalyticsSeries(
            points: response.data.compactMap { point in
                let timestamp = point.timestamp.value
                guard timestamp >= queryWindow.start, timestamp < queryWindow.endExclusive else {
                    return nil
                }
                return VercelAnalyticsPoint(timestamp: timestamp, visitors: point.visitors, pageViews: point.pageViews)
            },
            window: response.query.window
        )
    }

    func fetchTopBreakdown(
        for project: VercelProject,
        dimension: VercelAnalyticsDimension,
        range: VercelAnalyticsRange,
        now: Date
    ) async throws -> [VercelAnalyticsBreakdown] {
        let queryWindow = queryWindow(for: range, now: now)
        var query = analyticsQuery(for: project, window: queryWindow.aggregateWindow)
        query["by"] = dimension.rawValue
        query["limit"] = "5"

        let response = try await request(
            AnalyticsBreakdownResponseDTO.self,
            path: "/v1/query/web-analytics/visits/aggregate",
            query: query
        )

        let rows: [VercelAnalyticsBreakdown] = response.data.compactMap { point in
            guard let label = breakdownLabel(from: point, dimension: dimension) else {
                return nil
            }
            return VercelAnalyticsBreakdown(
                label: label,
                visitors: point.visitors,
                pageViews: point.pageViews
            )
        }
        return Array(rows.prefix(5))
    }

    private func breakdownLabel(
        from point: AnalyticsBreakdownPointDTO,
        dimension: VercelAnalyticsDimension
    ) -> String? {
        let rawLabel = switch dimension {
        case .requestPath:
            point.requestPath
        case .referrerHostname:
            point.referrerHostname
        }
        return normalizedBreakdownLabel(rawLabel, dimension: dimension)
    }

    private func analyticsQuery(
        for project: VercelProject,
        window: VercelAnalyticsWindow
    ) -> [String: String] {
        var query = [
            "filter": "environment eq 'production'",
            "projectId": project.id,
            "since": formatDate(window.since),
            "until": formatDate(window.until),
        ]
        if let teamID = project.teamID {
            query["teamId"] = teamID
        }
        return query
    }

    private func normalizedBreakdownLabel(
        _ rawLabel: String?,
        dimension: VercelAnalyticsDimension
    ) -> String? {
        guard let label = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return nil
        }
        guard label.caseInsensitiveCompare("Others") != .orderedSame else {
            return nil
        }
        if dimension == .referrerHostname {
            let normalizedLabel = label.lowercased()
            guard normalizedLabel != "direct", normalizedLabel != "(direct)" else {
                return nil
            }
        }
        return label
    }

    private func queryWindow(for range: VercelAnalyticsRange, now: Date) -> AnalyticsQueryWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let dayStart = calendar.startOfDay(for: now)

        switch range {
        case .last24Hours:
            let start = calendar.date(byAdding: .hour, value: -23, to: hourStart) ?? now
                .addingTimeInterval(-range.duration)
            let endExclusive = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now
            return AnalyticsQueryWindow(start: start, endExclusive: endExclusive)
        case .last7Days, .last30Days:
            let start = calendar.date(byAdding: .day, value: -Int(range.duration / (24 * 60 * 60)), to: dayStart)
                ?? now.addingTimeInterval(-range.duration)
            return AnalyticsQueryWindow(start: start, endExclusive: dayStart)
        }
    }
}
