import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelSkipsPopoverRefreshForFreshCachedSnapshot() async {
    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let harness = RefreshTestHarness(
        now: Date(timeIntervalSince1970: 1_785_549_630),
        cacheEntries: [
            SnapshotCacheEntry(projectID: "project-alpha", snapshot: snapshot),
        ]
    )

    await harness.connect()
    await harness.model.load()

    #expect(harness.model.state == .loaded(snapshot))
    #expect(harness.model.snapshotFreshness == .fresh)
    #expect(await harness.provider.requestedRanges.isEmpty)
}

@MainActor
@Test func snapshotRefreshCoordinatorOwnsCachePolicyAndSuccessfulPersistence() async throws {
    let cachedSnapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let cacheStore = InMemorySnapshotCacheStore(entries: [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: cachedSnapshot),
    ])
    let coordinator = SnapshotRefreshCoordinator(
        cacheStore: cacheStore,
        now: { Date(timeIntervalSince1970: 1_785_549_720) }
    )
    let request = SnapshotRefreshRequest(
        projectID: "project-alpha",
        range: .last7Days,
        trigger: .popoverOpen
    )

    let preparation = coordinator.prepare(request)
    #expect(preparation.cachedSnapshot == cachedSnapshot)
    #expect(preparation.freshness == .stale)
    #expect(preparation.shouldRequestLiveSnapshot)

    let provider = ControlledSnapshotProvider()
    let refresh = Task {
        try await coordinator.refresh(request, using: provider, isCurrent: { true })
    }
    await provider.waitUntilRequested()

    let liveSnapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 150,
        pageViews: 250,
        last24HoursVisitors: 15,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_720)
    )
    await provider.succeed(with: liveSnapshot)

    let result = try await refresh.value
    #expect(result == .accepted(liveSnapshot))
    #expect(cacheStore.entries == [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: liveSnapshot),
    ])
}

@MainActor
@Test func appModelPresentsStaleCacheBeforeLiveRefreshCompletes() async {
    let cachedSnapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let harness = RefreshTestHarness(cacheEntries: [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: cachedSnapshot),
    ])

    await harness.connect()
    let refresh = Task { await harness.model.load() }
    await harness.provider.waitUntilRequested()

    #expect(harness.model.state == .loaded(cachedSnapshot))
    #expect(harness.model.snapshotFreshness == .stale)

    let liveSnapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 150,
        pageViews: 250,
        last24HoursVisitors: 15,
        refreshedAt: harness.clock.now()
    )
    await harness.provider.succeed(with: liveSnapshot)
    await refresh.value

    #expect(harness.model.state == .loaded(liveSnapshot))
    #expect(harness.model.snapshotFreshness == .fresh)
    #expect(harness.cacheStore.entries == [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: liveSnapshot),
    ])
}

@MainActor
@Test func appModelCoalescesConcurrentRefreshes() async {
    let harness = RefreshTestHarness()

    await harness.connect()
    let firstRefresh = Task { await harness.model.load() }
    await harness.provider.waitUntilRequested()
    let secondRefresh = Task { await harness.model.load() }

    #expect(await harness.provider.requestedRanges == [.last7Days])

    await harness.provider.succeed(with: makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    ))
    await firstRefresh.value
    await secondRefresh.value

    #expect(await harness.provider.requestedRanges == [.last7Days])
}

@MainActor
@Test func appModelIgnoresAResultSupersededByProjectSelection() async {
    let alpha = VercelProject(id: "project-alpha", name: "Alpha")
    let beta = VercelProject(id: "project-beta", name: "Beta")
    let alphaProvider = ControlledSnapshotProvider()
    let betaProvider = ControlledSnapshotProvider()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [alpha, beta]) },
        analyticsProviderFactory: { _, project in
            project.id == alpha.id ? alphaProvider : betaProvider
        },
        launchAtLoginManager: InMemoryLaunchAtLoginManager(),
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    model.setProjectSelected(beta.id, selected: true)

    let alphaRefresh = Task { await model.load() }
    await alphaProvider.waitUntilRequested()
    let betaRefresh = Task { await model.selectProject(beta.id) }
    await betaProvider.waitUntilRequested()

    await alphaProvider.succeed(with: makeAnalyticsSnapshot(
        projectName: alpha.name,
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    ))
    await alphaRefresh.value
    #expect(model.state == .loading)

    let betaSnapshot = makeAnalyticsSnapshot(
        projectName: beta.name,
        visitors: 300,
        pageViews: 500,
        last24HoursVisitors: 22,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_660)
    )
    await betaProvider.succeed(with: betaSnapshot)
    await betaRefresh.value

    #expect(model.currentProjectID == beta.id)
    #expect(model.state == .loaded(betaSnapshot))
}

@MainActor
@Test func appModelKeepsCachedSnapshotWhenTransientRefreshFails() async {
    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let harness = RefreshTestHarness()

    await harness.connect()
    let initialRefresh = Task { await harness.model.load() }
    await harness.provider.waitUntilRequested()
    await harness.provider.succeed(with: snapshot)
    await initialRefresh.value

    let failedRefresh = Task { await harness.model.load() }
    await harness.provider.waitUntilRequested()
    let transientError = VercelAPIError.transient(status: 503, requestID: "fixture-request-id")
    await harness.provider.fail(with: transientError)
    await failedRefresh.value

    #expect(harness.model.state == .loaded(snapshot))
    #expect(harness.model.snapshotFreshness == .stale)
    #expect(harness.model.refreshMessage == transientError.localizedDescription)
}

@MainActor
@Test func appModelAppliesRateLimitBackoffAndManualRetryLimit() async {
    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let harness = RefreshTestHarness()
    let rateLimitError = VercelAPIError.rateLimited(
        metadata: VercelRateLimitMetadata(retryAfter: 1, requestID: "fixture-request-id")
    )

    await harness.connect()
    let initialRefresh = Task { await harness.model.load() }
    await harness.provider.waitUntilRequested()
    await harness.provider.succeed(with: snapshot)
    await initialRefresh.value

    let firstLimitedRefresh = Task { await harness.model.retryRefresh() }
    await harness.provider.waitUntilRequested()
    await harness.provider.fail(with: rateLimitError)
    await firstLimitedRefresh.value
    #expect(harness.model.retryAvailableAt == harness.clock.now().addingTimeInterval(1))

    for _ in 0 ..< 3 {
        harness.clock.advance(by: 2)
        let retry = Task { await harness.model.retryRefresh() }
        await harness.provider.waitUntilRequested()
        await harness.provider.fail(with: rateLimitError)
        await retry.value
    }

    let requestCountBeforeLimit = await harness.provider.requestedRanges.count
    harness.clock.advance(by: 2)
    await harness.model.retryRefresh()

    #expect(await harness.provider.requestedRanges.count == requestCountBeforeLimit)
    #expect(harness.model.refreshMessage == "Retry limit reached. Wait before trying again.")
}

@MainActor
@Test func appModelRefreshLoopUsesFiveMinuteInterval() async {
    let harness = RefreshTestHarness()

    await harness.connect()
    harness.model.startRefreshLoop()
    await harness.sleeper.waitUntilSleeping()
    #expect(await harness.sleeper.durations == [.seconds(300)])

    await harness.sleeper.release()
    await harness.provider.waitUntilRequested()
    await harness.provider.succeed(with: makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    ))
    harness.model.stopRefreshLoop()
    await harness.sleeper.release()
}
