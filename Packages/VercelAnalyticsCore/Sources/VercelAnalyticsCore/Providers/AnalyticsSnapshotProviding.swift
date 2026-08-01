public protocol AnalyticsSnapshotProviding: Sendable {
    func snapshot() async throws -> AnalyticsSnapshot
}
