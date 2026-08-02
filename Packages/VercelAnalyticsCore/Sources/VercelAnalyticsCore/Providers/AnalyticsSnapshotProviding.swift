public protocol AnalyticsSnapshotProviding: Sendable {
    func snapshot(for range: VercelAnalyticsRange) async throws -> AnalyticsSnapshot
}
