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
        let refreshRequest = SnapshotRefreshRequest(
            projectID: projectID,
            range: selectedRange,
            trigger: trigger
        )
        await snapshotRefreshCoordinator.refresh(
            refreshRequest,
            using: provider,
            showLoading: showLoading,
            eventHandler: { [weak self] event in self?.apply(event) }
        )
    }

    private func apply(_ event: SnapshotRefreshEvent) {
        switch event {
        case let .cached(snapshot, freshness):
            state = .loaded(snapshot)
            snapshotFreshness = freshness
            if freshness == .fresh, retryAvailableAt == nil {
                refreshMessage = nil
            }
        case .loading:
            state = .loading
            snapshotFreshness = .fresh
            refreshMessage = nil
        case let .succeeded(snapshot):
            state = .loaded(snapshot)
            snapshotFreshness = .fresh
            refreshMessage = nil
            retryAvailableAt = nil
        case let .blocked(message, retryAvailableAt):
            refreshMessage = message
            self.retryAvailableAt = retryAvailableAt
        case let .retryAvailabilityChanged(retryAvailableAt):
            self.retryAvailableAt = retryAvailableAt
        case let .recoverableFailure(snapshot, message, retryAvailableAt):
            state = .loaded(snapshot)
            snapshotFreshness = .stale
            refreshMessage = message
            self.retryAvailableAt = retryAvailableAt
        case let .failed(stateMessage, message, retryAvailableAt):
            state = .failed(stateMessage)
            snapshotFreshness = .fresh
            refreshMessage = message
            self.retryAvailableAt = retryAvailableAt
        }
    }
}
