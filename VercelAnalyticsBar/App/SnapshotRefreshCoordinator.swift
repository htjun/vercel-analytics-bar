import Foundation
import Observation
import VercelAnalyticsCore

enum RefreshTrigger: Equatable {
    case popoverOpen
    case periodic
    case projectSwitch
    case rangeChanged
    case manual
}

struct SnapshotCacheKey: Hashable {
    let projectID: String
    let range: VercelAnalyticsRange
}

enum SnapshotFreshness: Equatable {
    case fresh
    case stale
}

enum AnalyticsPresentationState: Equatable {
    case idle
    case loading
    case loaded(AnalyticsSnapshot)
    case empty(String)
    case failed(String)
}

struct SnapshotRefreshRequest {
    let projectID: String?
    let range: VercelAnalyticsRange
    let trigger: RefreshTrigger
}

struct SnapshotRefreshState: Equatable {
    static let idle = SnapshotRefreshState(
        content: .idle,
        freshness: .fresh,
        message: nil,
        retryAvailableAt: nil
    )

    let content: AnalyticsPresentationState
    let freshness: SnapshotFreshness
    let message: String?
    let retryAvailableAt: Date?
}

@MainActor
@Observable
final class SnapshotRefreshCoordinator {
    private struct RefreshPreparation {
        let cachedSnapshot: AnalyticsSnapshot?
        let freshness: SnapshotFreshness
        let shouldRequestLiveSnapshot: Bool
    }

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
    private let sleep: @Sendable (Duration) async throws -> Void
    private(set) var state = SnapshotRefreshState.idle
    private var cache: [SnapshotCacheKey: AnalyticsSnapshot]
    private var activeRefresh: ActiveRefresh?
    private var periodicRefreshTask: Task<Void, Never>?
    private var manualRetryCount = 0
    private var manualRetryWindowEndsAt: Date?
    private var nextRefreshAllowedAt: Date?

    init(
        cacheStore: any AnalyticsSnapshotCacheStore,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.cacheStore = cacheStore
        self.now = now
        self.sleep = sleep
        cache = Self.cacheDictionary(from: (try? cacheStore.read()) ?? [])
    }

    private func prepare(_ request: SnapshotRefreshRequest) -> RefreshPreparation {
        guard let cachedSnapshot = cachedSnapshot(for: request) else {
            return RefreshPreparation(
                cachedSnapshot: nil,
                freshness: .fresh,
                shouldRequestLiveSnapshot: true
            )
        }

        let freshness: SnapshotFreshness = isStale(cachedSnapshot) ? .stale : .fresh
        return RefreshPreparation(
            cachedSnapshot: cachedSnapshot,
            freshness: freshness,
            shouldRequestLiveSnapshot: request.trigger != .popoverOpen || freshness == .stale
        )
    }

    func refresh(
        _ request: SnapshotRefreshRequest,
        using provider: any AnalyticsSnapshotProviding,
        showLoading: Bool
    ) async {
        let requestKey = RequestKey(projectID: request.projectID, range: request.range)
        if let activeRefresh, activeRefresh.key != requestKey {
            activeRefresh.task.cancel()
            self.activeRefresh = nil
        }

        let preparation = prepare(request)
        if let cachedSnapshot = preparation.cachedSnapshot {
            presentCached(cachedSnapshot, freshness: preparation.freshness)
        }
        guard preparation.shouldRequestLiveSnapshot else { return }

        if let activeRefresh, activeRefresh.key == requestKey {
            await activeRefresh.task.value
            return
        }

        guard authorizeRefresh(trigger: request.trigger) else { return }

        if showLoading || preparation.cachedSnapshot == nil {
            state = SnapshotRefreshState(
                content: .loading,
                freshness: .fresh,
                message: nil,
                retryAvailableAt: nil
            )
        }

        let requestID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await performRefresh(
                request,
                using: provider,
                requestID: requestID
            )
        }
        activeRefresh = ActiveRefresh(id: requestID, key: requestKey, task: task)
        await task.value

        if activeRefresh?.id == requestID {
            activeRefresh = nil
        }
    }

    func reset() {
        cancelActiveRefresh()
        resetRetryPolicy()
    }

    func present(_ content: AnalyticsPresentationState) {
        state = SnapshotRefreshState(
            content: content,
            freshness: .fresh,
            message: nil,
            retryAvailableAt: nil
        )
    }

    func startPeriodicRefresh(_ refresh: @escaping @MainActor () async -> Void) {
        guard periodicRefreshTask == nil else { return }

        let sleep = sleep
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(.seconds(300))
                } catch {
                    return
                }
                guard !Task.isCancelled, self != nil else { return }
                await refresh()
            }
        }
    }

    func stop() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        cancelActiveRefresh()
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
        requestID: UUID
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
            state = SnapshotRefreshState(
                content: .loaded(snapshot),
                freshness: .fresh,
                message: nil,
                retryAvailableAt: nil
            )
        } catch is CancellationError {
            return
        } catch {
            guard activeRefresh?.id == requestID else { return }
            handleFailure(error, request: request)
        }
    }

    private func cancelActiveRefresh() {
        activeRefresh?.task.cancel()
        activeRefresh = nil
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

    private func presentCached(_ snapshot: AnalyticsSnapshot, freshness: SnapshotFreshness) {
        let message: String? = if freshness == .fresh, state.retryAvailableAt == nil {
            nil
        } else {
            state.message
        }
        state = SnapshotRefreshState(
            content: .loaded(snapshot),
            freshness: freshness,
            message: message,
            retryAvailableAt: state.retryAvailableAt
        )
    }
}

private extension SnapshotRefreshCoordinator {
    func authorizeRefresh(trigger: RefreshTrigger) -> Bool {
        let currentDate = now()
        if let manualRetryWindowEndsAt, currentDate >= manualRetryWindowEndsAt {
            manualRetryCount = 0
            self.manualRetryWindowEndsAt = nil
        }

        if let nextRefreshAllowedAt, currentDate < nextRefreshAllowedAt {
            state = SnapshotRefreshState(
                content: state.content,
                freshness: state.freshness,
                message: rateLimitMessage(for: nextRefreshAllowedAt),
                retryAvailableAt: nextRefreshAllowedAt
            )
            return false
        }

        if nextRefreshAllowedAt != nil {
            nextRefreshAllowedAt = nil
            state = SnapshotRefreshState(
                content: state.content,
                freshness: state.freshness,
                message: state.message,
                retryAvailableAt: nil
            )
        }

        guard trigger == .manual, manualRetryWindowEndsAt != nil else { return true }
        guard manualRetryCount < 3 else {
            state = SnapshotRefreshState(
                content: state.content,
                freshness: state.freshness,
                message: "Retry limit reached. Wait before trying again.",
                retryAvailableAt: state.retryAvailableAt
            )
            return false
        }
        manualRetryCount += 1
        return true
    }

    func handleFailure(_ error: any Error, request: SnapshotRefreshRequest) {
        let message: String
        let retryAvailableAt: Date?
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
            retryAvailableAt = state.retryAvailableAt
        }

        let fallbackSnapshot = request.projectID.flatMap {
            cachedSnapshot(projectID: $0, range: request.range)
        }
        if isRecoverable(error), let fallbackSnapshot {
            state = SnapshotRefreshState(
                content: .loaded(fallbackSnapshot),
                freshness: .stale,
                message: message,
                retryAvailableAt: retryAvailableAt
            )
        } else {
            state = SnapshotRefreshState(
                content: .failed(error.localizedDescription),
                freshness: .fresh,
                message: message,
                retryAvailableAt: retryAvailableAt
            )
        }
    }

    func isRecoverable(_ error: any Error) -> Bool {
        guard let error = error as? VercelAPIError else { return false }
        switch error {
        case .network, .transient, .rateLimited:
            return true
        case .missingToken, .authentication, .permissionDenied, .resourceNotFound, .requestRejected,
             .malformedResponse:
            return false
        }
    }

    func rateLimitDate(from metadata: VercelRateLimitMetadata) -> Date {
        let currentDate = now()
        let retryAfterDate = metadata.retryAfter.map { currentDate.addingTimeInterval($0) }
        return max(retryAfterDate ?? currentDate.addingTimeInterval(60), metadata.resetAt ?? .distantPast)
    }

    func rateLimitMessage(for date: Date) -> String {
        "Refresh paused until \(date.formatted(date: .omitted, time: .shortened))."
    }

    func resetRetryPolicy() {
        nextRefreshAllowedAt = nil
        manualRetryCount = 0
        manualRetryWindowEndsAt = nil
    }
}
