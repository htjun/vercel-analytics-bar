import Foundation
import VercelAnalyticsCore

enum RefreshTrigger: Equatable {
    case popoverOpen
    case periodic
    case projectSwitch
    case rangeChanged
    case manual
}

extension AppModel {
    func load() async {
        await load(trigger: .popoverOpen)
    }

    func startRefreshLoop() {
        guard refreshLoopTask == nil else { return }

        let sleep = sleep
        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(.seconds(300))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await load(trigger: .periodic)
            }
        }
    }

    func stopRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
    }

    func retryRefresh() async {
        await load(trigger: .manual)
    }

    func load(trigger: RefreshTrigger) async {
        if accountState == .connected {
            await loadLiveSnapshot(trigger: trigger)
            return
        }

        guard let provider else {
            state = .empty("Connect a Vercel account in Settings to load analytics.")
            return
        }
        await refreshSnapshot(using: provider, projectID: nil, trigger: trigger, showLoading: true)
    }

    func loadLiveSnapshot(trigger: RefreshTrigger) async {
        guard let analyticsProviderFactory else {
            state = .empty("Live analytics is not configured.")
            return
        }
        guard let project = currentProject else {
            state = .empty("Select a Vercel project in Settings to load analytics.")
            return
        }

        do {
            guard let token = try credentialStore.read() else {
                state = .empty("Connect a Vercel account in Settings to load analytics.")
                return
            }
            await refreshSnapshot(
                using: analyticsProviderFactory(token, project),
                projectID: project.id,
                trigger: trigger,
                showLoading: false
            )
        } catch {
            state = .failed("The Vercel account could not be read securely.")
        }
    }

    private func refreshSnapshot(
        using provider: any AnalyticsSnapshotProviding,
        projectID: String?,
        trigger: RefreshTrigger,
        showLoading: Bool
    ) async {
        let requestedRange = selectedRange
        let requestKey = RefreshRequestKey(projectID: projectID, range: requestedRange)
        let refreshRequest = SnapshotRefreshRequest(
            projectID: projectID,
            range: requestedRange,
            trigger: trigger
        )
        let preparation = snapshotRefreshCoordinator.prepare(refreshRequest)

        if let cachedSnapshot = preparation.cachedSnapshot {
            presentCachedSnapshot(cachedSnapshot, freshness: preparation.freshness)
        }
        guard preparation.shouldRequestLiveSnapshot else { return }

        if let activeRefreshKey, activeRefreshKey == requestKey, let activeRefreshTask {
            await activeRefreshTask.value
            return
        }

        guard canStartRefresh(trigger: trigger) else { return }

        activeRefreshTask?.cancel()
        let requestID = UUID()
        activeRefreshID = requestID
        activeRefreshKey = requestKey
        if showLoading || preparation.cachedSnapshot == nil {
            state = .loading
            snapshotFreshness = .fresh
            refreshMessage = nil
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await performRefresh(
                using: provider,
                request: refreshRequest,
                requestID: requestID
            )
        }
        activeRefreshTask = task
        await task.value

        if activeRefreshID == requestID {
            activeRefreshID = nil
            activeRefreshKey = nil
            activeRefreshTask = nil
        }
    }

    private func performRefresh(
        using provider: any AnalyticsSnapshotProviding,
        request: SnapshotRefreshRequest,
        requestID: UUID
    ) async {
        do {
            let result = try await snapshotRefreshCoordinator.refresh(
                request,
                using: provider,
                isCurrent: {
                    self.activeRefreshID == requestID
                        && request.range == self.selectedRange
                        && request.projectID == self.currentProjectID
                }
            )
            guard case let .accepted(snapshot) = result else { return }

            state = .loaded(snapshot)
            snapshotFreshness = .fresh
            refreshMessage = nil
            retryAvailableAt = nil
            nextRefreshAllowedAt = nil
            manualRetryCount = 0
            manualRetryWindowEndsAt = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeRefreshID == requestID,
                  request.range == selectedRange,
                  request.projectID == currentProjectID
            else { return }
            handleRefreshFailure(error, projectID: request.projectID, range: request.range)
        }
    }

    private func presentCachedSnapshot(
        _ snapshot: AnalyticsSnapshot,
        freshness: SnapshotFreshness
    ) {
        state = .loaded(snapshot)
        snapshotFreshness = freshness
        if snapshotFreshness == .fresh, retryAvailableAt == nil {
            refreshMessage = nil
        }
    }

    private func canStartRefresh(trigger: RefreshTrigger) -> Bool {
        let currentDate = now()
        if let manualRetryWindowEndsAt, currentDate >= manualRetryWindowEndsAt {
            manualRetryCount = 0
            self.manualRetryWindowEndsAt = nil
        }

        if let nextRefreshAllowedAt, currentDate < nextRefreshAllowedAt {
            refreshMessage = rateLimitMessage(for: nextRefreshAllowedAt)
            return false
        }

        if nextRefreshAllowedAt != nil {
            nextRefreshAllowedAt = nil
            retryAvailableAt = nil
        }

        guard trigger == .manual, manualRetryWindowEndsAt != nil else { return true }
        guard manualRetryCount < 3 else {
            refreshMessage = "Retry limit reached. Wait before trying again."
            return false
        }
        manualRetryCount += 1
        return true
    }

    private func handleRefreshFailure(
        _ error: any Error,
        projectID: String?,
        range: VercelAnalyticsRange
    ) {
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
            refreshMessage = rateLimitMessage(for: availableAt)
        } else {
            refreshMessage = error.localizedDescription
        }

        guard isRecoverable(error),
              let projectID,
              let cachedSnapshot = snapshotRefreshCoordinator.cachedSnapshot(projectID: projectID, range: range)
        else {
            state = .failed(error.localizedDescription)
            snapshotFreshness = .fresh
            return
        }

        state = .loaded(cachedSnapshot)
        snapshotFreshness = .stale
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
}
