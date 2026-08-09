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

enum SnapshotRefreshEvent: Equatable {
    case cached(AnalyticsSnapshot, freshness: SnapshotFreshness)
    case loading
    case succeeded(AnalyticsSnapshot)
    case blocked(message: String, retryAvailableAt: Date?)
    case retryAvailabilityChanged(Date?)
    case recoverableFailure(AnalyticsSnapshot, message: String, retryAvailableAt: Date?)
    case failed(stateMessage: String, message: String, retryAvailableAt: Date?)
}

@MainActor
final class SnapshotRefreshCoordinator {
    private struct RequestKey: Hashable {
        let projectID: String?
        let range: VercelAnalyticsRange
    }

    private struct ActiveRefresh {
        let id: UUID
        let key: RequestKey
        let task: Task<Void, Never>
    }

    private let cacheStore: any AnalyticsSnapshotCacheStore
    private let now: @Sendable () -> Date
    private var cache: [SnapshotCacheKey: AnalyticsSnapshot]
    private var activeRefresh: ActiveRefresh?
    private var manualRetryCount = 0
    private var manualRetryWindowEndsAt: Date?
    private var nextRefreshAllowedAt: Date?
    private var retryAvailableAt: Date?

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
        showLoading: Bool,
        eventHandler: @escaping @MainActor (SnapshotRefreshEvent) -> Void
    ) async {
        let requestKey = RequestKey(projectID: request.projectID, range: request.range)
        if let activeRefresh, activeRefresh.key != requestKey {
            activeRefresh.task.cancel()
            self.activeRefresh = nil
        }

        let preparation = prepare(request)
        if let cachedSnapshot = preparation.cachedSnapshot {
            eventHandler(.cached(cachedSnapshot, freshness: preparation.freshness))
        }
        guard preparation.shouldRequestLiveSnapshot else { return }

        if let activeRefresh, activeRefresh.key == requestKey {
            await activeRefresh.task.value
            return
        }

        guard authorizeRefresh(trigger: request.trigger, eventHandler: eventHandler) else { return }

        if showLoading || preparation.cachedSnapshot == nil {
            eventHandler(.loading)
        }

        let requestID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await performRefresh(
                request,
                using: provider,
                requestID: requestID,
                eventHandler: eventHandler
            )
        }
        activeRefresh = ActiveRefresh(id: requestID, key: requestKey, task: task)
        await task.value

        if activeRefresh?.id == requestID {
            activeRefresh = nil
        }
    }

    func reset() {
        activeRefresh?.task.cancel()
        activeRefresh = nil
        resetRetryPolicy()
    }

    private func cachedSnapshot(projectID: String, range: VercelAnalyticsRange) -> AnalyticsSnapshot? {
        cache[SnapshotCacheKey(projectID: projectID, range: range)]
    }

    func clearCache() throws {
        try cacheStore.clear()
        cache.removeAll()
    }

    private func performRefresh(
        _ request: SnapshotRefreshRequest,
        using provider: any AnalyticsSnapshotProviding,
        requestID: UUID,
        eventHandler: @escaping @MainActor (SnapshotRefreshEvent) -> Void
    ) async {
        do {
            try Task.checkCancellation()
            let snapshot = try await provider.snapshot(for: request.range)
            try Task.checkCancellation()
            guard activeRefresh?.id == requestID else { return }

            if let projectID = request.projectID {
                cache[SnapshotCacheKey(projectID: projectID, range: request.range)] = snapshot
                persistCache()
            }
            resetRetryPolicy()
            eventHandler(.succeeded(snapshot))
        } catch is CancellationError {
            return
        } catch {
            guard activeRefresh?.id == requestID else { return }
            handleFailure(error, request: request, eventHandler: eventHandler)
        }
    }

    private func authorizeRefresh(
        trigger: RefreshTrigger,
        eventHandler: @MainActor (SnapshotRefreshEvent) -> Void
    ) -> Bool {
        let currentDate = now()
        if let manualRetryWindowEndsAt, currentDate >= manualRetryWindowEndsAt {
            manualRetryCount = 0
            self.manualRetryWindowEndsAt = nil
        }

        if let nextRefreshAllowedAt, currentDate < nextRefreshAllowedAt {
            eventHandler(.blocked(
                message: rateLimitMessage(for: nextRefreshAllowedAt),
                retryAvailableAt: nextRefreshAllowedAt
            ))
            return false
        }

        if nextRefreshAllowedAt != nil {
            nextRefreshAllowedAt = nil
            retryAvailableAt = nil
            eventHandler(.retryAvailabilityChanged(nil))
        }

        guard trigger == .manual, manualRetryWindowEndsAt != nil else { return true }
        guard manualRetryCount < 3 else {
            eventHandler(.blocked(
                message: "Retry limit reached. Wait before trying again.",
                retryAvailableAt: retryAvailableAt
            ))
            return false
        }
        manualRetryCount += 1
        return true
    }

    private func handleFailure(
        _ error: any Error,
        request: SnapshotRefreshRequest,
        eventHandler: @MainActor (SnapshotRefreshEvent) -> Void
    ) {
        let message: String
        if case let .rateLimited(metadata) = error as? VercelAPIError {
            let availableAt = rateLimitDate(from: metadata)
            nextRefreshAllowedAt = availableAt
            retryAvailableAt = availableAt
            if let windowEnd = manualRetryWindowEndsAt, now() < windowEnd {
                // Keep the existing manual retry window and count.
            } else {
                manualRetryCount = 0
                manualRetryWindowEndsAt = now().addingTimeInterval(300)
            }
            message = rateLimitMessage(for: availableAt)
        } else {
            message = error.localizedDescription
        }

        let fallbackSnapshot = request.projectID.flatMap {
            cachedSnapshot(projectID: $0, range: request.range)
        }
        if isRecoverable(error), let fallbackSnapshot {
            eventHandler(.recoverableFailure(
                fallbackSnapshot,
                message: message,
                retryAvailableAt: retryAvailableAt
            ))
        } else {
            eventHandler(.failed(
                stateMessage: error.localizedDescription,
                message: message,
                retryAvailableAt: retryAvailableAt
            ))
        }
    }

    private func isRecoverable(_ error: any Error) -> Bool {
        guard let error = error as? VercelAPIError else { return false }
        switch error {
        case .network, .transient, .rateLimited:
            return true
        case .missingToken, .authentication, .permissionDenied, .resourceNotFound, .requestRejected,
             .malformedResponse:
            return false
        }
    }

    private func rateLimitDate(from metadata: VercelRateLimitMetadata) -> Date {
        let currentDate = now()
        let retryAfterDate = metadata.retryAfter.map { currentDate.addingTimeInterval($0) }
        return max(retryAfterDate ?? currentDate.addingTimeInterval(60), metadata.resetAt ?? .distantPast)
    }

    private func rateLimitMessage(for date: Date) -> String {
        "Refresh paused until \(date.formatted(date: .omitted, time: .shortened))."
    }

    private func resetRetryPolicy() {
        retryAvailableAt = nil
        nextRefreshAllowedAt = nil
        manualRetryCount = 0
        manualRetryWindowEndsAt = nil
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
