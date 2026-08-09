import Foundation
import VercelAnalyticsCore

struct SnapshotCacheKey: Hashable {
    let projectID: String
    let range: VercelAnalyticsRange
}

enum SnapshotFreshness: Equatable {
    case fresh
    case stale
}

struct SnapshotRefreshRequest {
    let projectID: String?
    let range: VercelAnalyticsRange
    let trigger: RefreshTrigger
}

struct SnapshotRefreshPreparation: Equatable {
    let cachedSnapshot: AnalyticsSnapshot?
    let freshness: SnapshotFreshness
    let shouldRequestLiveSnapshot: Bool
}

enum SnapshotRefreshResult: Equatable {
    case accepted(AnalyticsSnapshot)
    case superseded
}

@MainActor
final class SnapshotRefreshCoordinator {
    private let cacheStore: any AnalyticsSnapshotCacheStore
    private let now: @Sendable () -> Date
    private var cache: [SnapshotCacheKey: AnalyticsSnapshot]

    init(
        cacheStore: any AnalyticsSnapshotCacheStore,
        now: @escaping @Sendable () -> Date
    ) {
        self.cacheStore = cacheStore
        self.now = now
        cache = Self.cacheDictionary(from: (try? cacheStore.read()) ?? [])
    }

    func prepare(_ request: SnapshotRefreshRequest) -> SnapshotRefreshPreparation {
        guard let cachedSnapshot = cachedSnapshot(for: request) else {
            return SnapshotRefreshPreparation(
                cachedSnapshot: nil,
                freshness: .fresh,
                shouldRequestLiveSnapshot: true
            )
        }

        let freshness: SnapshotFreshness = isStale(cachedSnapshot) ? .stale : .fresh
        return SnapshotRefreshPreparation(
            cachedSnapshot: cachedSnapshot,
            freshness: freshness,
            shouldRequestLiveSnapshot: request.trigger != .popoverOpen || freshness == .stale
        )
    }

    func refresh(
        _ request: SnapshotRefreshRequest,
        using provider: any AnalyticsSnapshotProviding,
        isCurrent: () -> Bool
    ) async throws -> SnapshotRefreshResult {
        try Task.checkCancellation()
        let snapshot = try await provider.snapshot(for: request.range)
        try Task.checkCancellation()
        guard isCurrent() else { return .superseded }

        if let projectID = request.projectID {
            cache[SnapshotCacheKey(projectID: projectID, range: request.range)] = snapshot
            persistCache()
        }
        return .accepted(snapshot)
    }

    func cachedSnapshot(projectID: String, range: VercelAnalyticsRange) -> AnalyticsSnapshot? {
        cache[SnapshotCacheKey(projectID: projectID, range: range)]
    }

    func clearCache() throws {
        try cacheStore.clear()
        cache.removeAll()
    }

    private func cachedSnapshot(for request: SnapshotRefreshRequest) -> AnalyticsSnapshot? {
        guard let projectID = request.projectID else { return nil }
        return cachedSnapshot(projectID: projectID, range: request.range)
    }

    private func isStale(_ snapshot: AnalyticsSnapshot) -> Bool {
        now().timeIntervalSince(snapshot.refreshedAt) > 60
    }

    private func persistCache() {
        let entries = cache.map { key, snapshot in
            SnapshotCacheEntry(projectID: key.projectID, snapshot: snapshot)
        }
        try? cacheStore.write(entries)
    }

    private static func cacheDictionary(
        from entries: [SnapshotCacheEntry]
    ) -> [SnapshotCacheKey: AnalyticsSnapshot] {
        entries.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.snapshot
        }
    }
}
