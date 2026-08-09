import Foundation

public protocol VercelHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public protocol VercelProjectListingProviding: Sendable {
    func listAccessibleProjects() async throws -> [VercelProject]
}

public struct URLSessionVercelHTTPTransport: VercelHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct VercelRateLimitMetadata: Equatable, Sendable {
    public let limit: Int?
    public let remaining: Int?
    public let resetAt: Date?
    public let retryAfter: TimeInterval?
    public let requestID: String?

    public init(
        limit: Int? = nil,
        remaining: Int? = nil,
        resetAt: Date? = nil,
        retryAfter: TimeInterval? = nil,
        requestID: String? = nil
    ) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.retryAfter = retryAfter
        self.requestID = requestID
    }
}

public enum VercelAPIError: Error, Equatable, LocalizedError, Sendable {
    case missingToken
    case authentication(status: Int)
    case permissionDenied(status: Int)
    case rateLimited(metadata: VercelRateLimitMetadata)
    case transient(status: Int, requestID: String?)
    case resourceNotFound(status: Int)
    case requestRejected(status: Int)
    case network
    case malformedResponse(endpoint: String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "A Vercel access token is required."
        case .authentication:
            "Vercel authentication failed."
        case .permissionDenied:
            "Vercel denied access to this resource."
        case .rateLimited:
            "Vercel rate limited the request."
        case .transient:
            "Vercel is temporarily unavailable."
        case .resourceNotFound:
            "Vercel could not find the requested resource."
        case .requestRejected:
            "Vercel rejected the request."
        case .network:
            "The request to Vercel could not be completed."
        case .malformedResponse:
            "Vercel returned an invalid response."
        }
    }
}

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

public struct VercelAPIClient: Sendable, VercelProjectListingProviding {
    public static let defaultBaseURL = URL(string: "https://api.vercel.com")!

    private let token: String
    private let baseURL: URL
    private let transport: any VercelHTTPTransport

    public init(
        token: String,
        baseURL: URL = VercelAPIClient.defaultBaseURL,
        transport: any VercelHTTPTransport = URLSessionVercelHTTPTransport()
    ) {
        self.token = token
        self.baseURL = baseURL
        self.transport = transport
    }

    public func validateToken() async throws {
        _ = try await request(TeamsResponseDTO.self, path: "/v2/teams", query: ["limit": "1"])
    }

    public func listTeams() async throws -> [VercelTeam] {
        var teams: [VercelTeam] = []
        var cursor: String?
        var seenCursors = Set<String>()

        while true {
            var query = ["limit": "100"]
            if let cursor {
                query["until"] = cursor
            }

            let response = try await request(TeamsResponseDTO.self, path: "/v2/teams", query: query)
            teams.append(contentsOf: response.teams.map { VercelTeam(id: $0.id, name: $0.name, slug: $0.slug) })

            guard let next = response.pagination.next else {
                return teams
            }
            guard seenCursors.insert(next).inserted else {
                throw VercelAPIError.malformedResponse(endpoint: "/v2/teams")
            }
            cursor = next
        }
    }

    public func listProjects(
        teamID: String? = nil,
        teamName: String? = nil,
        scopeSlug: String? = nil
    ) async throws -> [VercelProject] {
        var projects: [VercelProject] = []
        var cursor: String?
        var seenCursors = Set<String>()

        while true {
            var query = ["limit": "100"]
            if let teamID {
                query["teamId"] = teamID
            }
            if let cursor {
                query["until"] = cursor
            }

            let response = try await request(ProjectsResponseDTO.self, path: "/v9/projects", query: query)
            projects.append(contentsOf: response.projects.map {
                VercelProject(
                    id: $0.id,
                    name: $0.name,
                    teamID: teamID,
                    teamName: teamName,
                    scopeSlug: scopeSlug
                )
            })

            guard let next = response.pagination.next else {
                return projects
            }
            guard seenCursors.insert(next).inserted else {
                throw VercelAPIError.malformedResponse(endpoint: "/v9/projects")
            }
            cursor = next
        }
    }

    public func listAccessibleProjects() async throws -> [VercelProject] {
        let user = try await request(AuthenticatedUserResponseDTO.self, path: "/v2/user", query: [:]).user
        let teams = try await listTeams()
        var projects = try await listProjects(scopeSlug: user.username)

        for team in teams {
            let teamProjects = try await listProjects(
                teamID: team.id,
                teamName: team.name,
                scopeSlug: team.slug
            )
            projects.append(contentsOf: teamProjects)
        }

        var uniqueProjectsByID: [String: VercelProject] = [:]
        for project in projects {
            if project.teamID != nil || uniqueProjectsByID[project.id] == nil {
                uniqueProjectsByID[project.id] = project
            }
        }

        return VercelProject.sorted(Array(uniqueProjectsByID.values))
    }

    public func fetchCount(
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

    public func fetchSeries(
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

    public func fetchTopBreakdown(
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
            let rawLabel = switch dimension {
            case .requestPath:
                point.requestPath
            case .referrerHostname:
                point.referrerHostname
            }
            guard let label = normalizedBreakdownLabel(rawLabel, dimension: dimension) else {
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

    private func request<Response: Decodable>(
        _ responseType: Response.Type,
        path: String,
        query: [String: String]
    ) async throws -> Response {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VercelAPIError.missingToken
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components?.url else {
            throw VercelAPIError.malformedResponse(endpoint: path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await transport.data(for: request)
        } catch {
            throw VercelAPIError.network
        }

        guard let response = urlResponse as? HTTPURLResponse else {
            throw VercelAPIError.malformedResponse(endpoint: path)
        }
        try throwIfNeeded(for: response, endpoint: path)

        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw VercelAPIError.malformedResponse(endpoint: path)
        }
    }

    private func throwIfNeeded(for response: HTTPURLResponse, endpoint: String) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw VercelAPIError.authentication(status: response.statusCode)
        case 403 where endpoint == "/v2/teams":
            throw VercelAPIError.authentication(status: response.statusCode)
        case 403:
            throw VercelAPIError.permissionDenied(status: response.statusCode)
        case 429:
            throw VercelAPIError.rateLimited(metadata: rateLimitMetadata(from: response))
        case 404:
            throw VercelAPIError.resourceNotFound(status: response.statusCode)
        case 408, 425, 500 ... 599:
            throw VercelAPIError.transient(status: response.statusCode, requestID: requestID(from: response))
        default:
            throw VercelAPIError.requestRejected(status: response.statusCode)
        }
    }

    private func analyticsQuery(for project: VercelProject, window: VercelAnalyticsWindow) -> [String: String] {
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

    private func rateLimitMetadata(from response: HTTPURLResponse) -> VercelRateLimitMetadata {
        VercelRateLimitMetadata(
            limit: integerHeader("X-RateLimit-Limit", from: response),
            remaining: integerHeader("X-RateLimit-Remaining", from: response),
            resetAt: dateHeader("X-RateLimit-Reset", from: response),
            retryAfter: timeIntervalHeader("Retry-After", from: response),
            requestID: requestID(from: response)
        )
    }

    private func integerHeader(_ name: String, from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: name) else { return nil }
        return Int(value)
    }

    private func dateHeader(_ name: String, from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: name), let timestamp = Double(value) else {
            return nil
        }
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    private func timeIntervalHeader(_ name: String, from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: name) else { return nil }
        return TimeInterval(value)
    }

    private func requestID(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "X-Vercel-Id")
    }
}
