import VercelAnalyticsCore

extension AppModel {
    func load() async {
        await load(trigger: .popoverOpen)
    }

    func startRefreshLoop() {
        snapshotRefreshCoordinator.startPeriodicRefresh { [weak self] in
            await self?.load(trigger: .periodic)
        }
    }

    func stopRefreshLoop() {
        snapshotRefreshCoordinator.stop()
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
            snapshotRefreshCoordinator.present(.empty("Connect a Vercel account in Settings to load analytics."))
            return
        }
        await refreshSnapshot(using: provider, projectID: nil, trigger: trigger, showLoading: true)
    }

    func loadLiveSnapshot(trigger: RefreshTrigger) async {
        guard let analyticsProviderFactory else {
            snapshotRefreshCoordinator.present(.empty("Live analytics is not configured."))
            return
        }
        guard let project = currentProject else {
            snapshotRefreshCoordinator.present(.empty("Select a Vercel project in Settings to load analytics."))
            return
        }

        do {
            guard let token = try credentialStore.read() else {
                snapshotRefreshCoordinator
                    .present(.empty("Connect a Vercel account in Settings to load analytics."))
                return
            }
            await refreshSnapshot(
                using: analyticsProviderFactory(token, project),
                projectID: project.id,
                trigger: trigger,
                showLoading: false
            )
        } catch {
            snapshotRefreshCoordinator.present(.failed("The Vercel account could not be read securely."))
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
            showLoading: showLoading
        )
    }
}
