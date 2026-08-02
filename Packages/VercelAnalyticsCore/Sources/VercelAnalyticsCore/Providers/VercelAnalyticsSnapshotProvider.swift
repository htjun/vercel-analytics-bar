import Foundation

public struct VercelAnalyticsSnapshotProvider: AnalyticsSnapshotProviding {
    private let client: VercelAPIClient
    private let project: VercelProject
    private let now: @Sendable () -> Date

    public init(
        token: String,
        project: VercelProject,
        now: @escaping @Sendable () -> Date = Date.init,
        baseURL: URL = VercelAPIClient.defaultBaseURL,
        transport: any VercelHTTPTransport = URLSessionVercelHTTPTransport()
    ) {
        client = VercelAPIClient(token: token, baseURL: baseURL, transport: transport)
        self.project = project
        self.now = now
    }

    public func snapshot() async throws -> AnalyticsSnapshot {
        let refreshedAt = now()
        let count = try await client.fetchCount(
            for: project,
            range: .last24Hours,
            now: refreshedAt
        )

        return AnalyticsSnapshot(
            projectName: project.name,
            primaryMetric: AnalyticsMetric(label: "Visitors", value: count.visitors),
            refreshedAt: refreshedAt
        )
    }
}
