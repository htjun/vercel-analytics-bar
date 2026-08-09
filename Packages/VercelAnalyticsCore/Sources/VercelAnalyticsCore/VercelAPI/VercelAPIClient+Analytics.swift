import Foundation

private let breakdownDisplayLimit = 5
private let breakdownCandidateLimit = breakdownDisplayLimit * 2

public extension VercelAPIClient {
    func fetchCount(
        for project: VercelProject,
        range: VercelAnalyticsRange,
        now: Date
    ) async throws -> VercelAnalyticsCount {
        try await fetchCount(for: project, window: range.plan(at: now).currentWindow)
    }

    internal func fetchCount(
        for project: VercelProject,
        window: VercelAnalyticsInterval
    ) async throws -> VercelAnalyticsCount {
        let response = try await request(
            AnalyticsCountResponseDTO.self,
            path: "/v1/query/web-analytics/visits/count",
            query: analyticsQuery(for: project, window: window.countWindow)
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
        let plan = range.plan(at: now)
        return try await fetchSeries(for: project, window: plan.currentWindow, bucket: plan.bucket)
    }

    internal func fetchSeries(
        for project: VercelProject,
        window: VercelAnalyticsInterval,
        bucket: VercelAnalyticsBucket
    ) async throws -> VercelAnalyticsSeries {
        var query = analyticsQuery(for: project, window: window.aggregateWindow)
        query["by"] = bucket.queryValue

        let response = try await request(
            AnalyticsSeriesResponseDTO.self,
            path: "/v1/query/web-analytics/visits/aggregate",
            query: query
        )

        return VercelAnalyticsSeries(
            points: response.data.compactMap { point in
                let timestamp = point.timestamp.value
                guard timestamp >= window.start, timestamp < window.endExclusive else {
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
        try await fetchTopBreakdown(
            for: project,
            dimension: dimension,
            window: range.plan(at: now).currentWindow
        )
    }

    internal func fetchTopBreakdown(
        for project: VercelProject,
        dimension: VercelAnalyticsDimension,
        window: VercelAnalyticsInterval
    ) async throws -> [VercelAnalyticsBreakdown] {
        var query = analyticsQuery(for: project, window: window.aggregateWindow)
        query["by"] = dimension.rawValue
        query["limit"] = String(breakdownCandidateLimit)

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
        return Array(rows.prefix(breakdownDisplayLimit))
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
}

private extension VercelAnalyticsInterval {
    var countWindow: VercelAnalyticsWindow {
        VercelAnalyticsWindow(since: start, until: endExclusive)
    }

    var aggregateWindow: VercelAnalyticsWindow {
        VercelAnalyticsWindow(since: start, until: endExclusive.addingTimeInterval(-0.001))
    }
}

private extension VercelAnalyticsBucket {
    var queryValue: String {
        switch self {
        case .hour:
            "hour"
        case .day:
            "day"
        }
    }
}
