import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func snapshotRefreshCoordinatorOwnsCachePolicyAndSuccessfulPersistence() async {
    let cachedSnapshot = refreshFixture()
    let cacheStore = InMemorySnapshotCacheStore(entries: [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: cachedSnapshot),
    ])
    let driver = SnapshotRefreshTestDriver(cacheStore: cacheStore)
    let refresh = driver.start(refreshRequest())
    await driver.provider.waitUntilRequested()
    #expect(driver.coordinator.state == refreshState(
        content: .loaded(cachedSnapshot),
        freshness: .stale
    ))

    let liveSnapshot = refreshFixture(visitors: 150, refreshedAt: refreshNow)
    await driver.provider.succeed(with: liveSnapshot)
    await refresh.value

    #expect(driver.coordinator.state == refreshState(content: .loaded(liveSnapshot)))
    #expect(cacheStore.entries == [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: liveSnapshot),
    ])
}

@MainActor
@Test func snapshotRefreshCoordinatorSkipsPopoverRefreshForFreshCache() async {
    let snapshot = refreshFixture(refreshedAt: refreshNow)
    let driver = SnapshotRefreshTestDriver(cacheEntries: [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: snapshot),
    ])

    await driver.run(refreshRequest())

    #expect(await driver.provider.requestedRanges.isEmpty)
    #expect(driver.coordinator.state == refreshState(content: .loaded(snapshot)))
}

@MainActor
@Test func snapshotRefreshCoordinatorCoalescesConcurrentRequests() async {
    let driver = SnapshotRefreshTestDriver()
    let request = refreshRequest(trigger: .periodic)

    let firstRefresh = driver.start(request)
    await driver.provider.waitUntilRequested()
    #expect(driver.coordinator.state == refreshState(content: .loading))
    let secondRefresh = driver.start(request)

    #expect(await driver.provider.requestedRanges == [.last7Days])

    let snapshot = refreshFixture()
    await driver.provider.succeed(with: snapshot)
    await firstRefresh.value
    await secondRefresh.value

    #expect(await driver.provider.requestedRanges == [.last7Days])
    #expect(driver.coordinator.state == refreshState(content: .loaded(snapshot)))
}

@MainActor
@Test func snapshotRefreshCoordinatorIgnoresSupersededResults() async {
    let driver = SnapshotRefreshTestDriver()
    let betaProvider = ControlledSnapshotProvider()
    let alphaRequest = refreshRequest(trigger: .periodic)
    let betaRequest = refreshRequest(projectID: "project-beta", trigger: .projectSwitch)

    let alphaRefresh = driver.start(alphaRequest, showLoading: true)
    await driver.provider.waitUntilRequested()
    let betaRefresh = driver.start(betaRequest, using: betaProvider, showLoading: true)
    await betaProvider.waitUntilRequested()

    let alphaSnapshot = refreshFixture()
    await driver.provider.succeed(with: alphaSnapshot)
    await alphaRefresh.value
    #expect(driver.coordinator.state == refreshState(content: .loading))

    let betaSnapshot = refreshFixture(projectName: "Beta", visitors: 300)
    await betaProvider.succeed(with: betaSnapshot)
    await betaRefresh.value
    #expect(driver.coordinator.state == refreshState(content: .loaded(betaSnapshot)))
}

@MainActor
@Test func snapshotRefreshCoordinatorKeepsCacheOnTransientFailure() async {
    let snapshot = refreshFixture()
    let driver = SnapshotRefreshTestDriver(cacheEntries: [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: snapshot),
    ])
    let transientError = VercelAPIError.transient(status: 503, requestID: "fixture-request-id")

    await failRefresh(driver, request: refreshRequest(trigger: .periodic), error: transientError)

    #expect(driver.coordinator.state == refreshState(
        content: .loaded(snapshot),
        freshness: .stale,
        message: transientError.localizedDescription,
        retryAvailableAt: nil
    ))
}

@MainActor
@Test func snapshotRefreshCoordinatorStopCancelsAnActiveRequest() async {
    let driver = SnapshotRefreshTestDriver()
    let refresh = driver.start(refreshRequest(trigger: .periodic))
    await driver.provider.waitUntilRequested()

    driver.coordinator.stop()
    let snapshot = refreshFixture()
    await driver.provider.succeed(with: snapshot)
    await refresh.value

    #expect(driver.coordinator.state == refreshState(content: .loading))
}

@MainActor
@Test func snapshotRefreshCoordinatorAppliesRateLimitAndManualRetryPolicy() async {
    let snapshot = refreshFixture()
    let clock = MutableDateClock(date: refreshNow)
    let driver = SnapshotRefreshTestDriver(
        clock: clock,
        cacheEntries: [SnapshotCacheEntry(projectID: "project-alpha", snapshot: snapshot)]
    )
    let request = refreshRequest(trigger: .manual)
    let rateLimitError = VercelAPIError.rateLimited(
        metadata: VercelRateLimitMetadata(retryAfter: 1, requestID: "fixture-request-id")
    )

    await failRefresh(driver, request: request, error: rateLimitError)
    let availableAt = clock.now().addingTimeInterval(1)
    let message = "Refresh paused until \(availableAt.formatted(date: .omitted, time: .shortened))."
    #expect(driver.coordinator.state == refreshState(
        content: .loaded(snapshot),
        freshness: .stale,
        message: message,
        retryAvailableAt: availableAt
    ))

    for _ in 0 ..< 3 {
        clock.advance(by: 2)
        await failRefresh(driver, request: request, error: rateLimitError)
    }

    let requestCountBeforeLimit = await driver.provider.requestedRanges.count
    clock.advance(by: 2)
    await driver.run(request)
    #expect(await driver.provider.requestedRanges.count == requestCountBeforeLimit)
    #expect(driver.coordinator.state == refreshState(
        content: .loaded(snapshot),
        freshness: .stale,
        message: "Retry limit reached. Wait before trying again.",
        retryAvailableAt: nil
    ))

    clock.advance(by: 300)
    let resetRetry = driver.start(request)
    await driver.provider.waitUntilRequested()
    await driver.provider.succeed(with: snapshot)
    await resetRetry.value
    #expect(await driver.provider.requestedRanges.count == requestCountBeforeLimit + 1)
    #expect(driver.coordinator.state == refreshState(content: .loaded(snapshot)))
}

@MainActor
private final class SnapshotRefreshTestDriver {
    let provider: ControlledSnapshotProvider
    let coordinator: SnapshotRefreshCoordinator

    init(
        provider: ControlledSnapshotProvider = ControlledSnapshotProvider(),
        clock: MutableDateClock = MutableDateClock(date: refreshNow),
        cacheStore: InMemorySnapshotCacheStore? = nil,
        cacheEntries: [SnapshotCacheEntry] = []
    ) {
        self.provider = provider
        coordinator = SnapshotRefreshCoordinator(
            cacheStore: cacheStore ?? InMemorySnapshotCacheStore(entries: cacheEntries),
            now: { clock.now() }
        )
    }

    func start(
        _ request: SnapshotRefreshRequest,
        using provider: (any AnalyticsSnapshotProviding)? = nil,
        showLoading: Bool = false
    ) -> Task<Void, Never> {
        Task { await run(request, using: provider, showLoading: showLoading) }
    }

    func run(
        _ request: SnapshotRefreshRequest,
        using provider: (any AnalyticsSnapshotProviding)? = nil,
        showLoading: Bool = false
    ) async {
        await coordinator.refresh(
            request,
            using: provider ?? self.provider,
            showLoading: showLoading
        )
    }
}

@MainActor
private func failRefresh(
    _ driver: SnapshotRefreshTestDriver,
    request: SnapshotRefreshRequest,
    error: any Error
) async {
    let refresh = driver.start(request)
    await driver.provider.waitUntilRequested()
    await driver.provider.fail(with: error)
    await refresh.value
}

private func refreshRequest(
    projectID: String = "project-alpha",
    trigger: RefreshTrigger = .popoverOpen
) -> SnapshotRefreshRequest {
    SnapshotRefreshRequest(projectID: projectID, range: .last7Days, trigger: trigger)
}

private func refreshFixture(
    projectName: String = "Alpha",
    visitors: Int = 100,
    refreshedAt: Date = Date(timeIntervalSince1970: 1_785_549_600)
) -> AnalyticsSnapshot {
    makeAnalyticsSnapshot(
        projectName: projectName,
        visitors: visitors,
        pageViews: visitors * 2,
        last24HoursVisitors: visitors / 10,
        refreshedAt: refreshedAt
    )
}

private func refreshState(
    content: AnalyticsPresentationState,
    freshness: SnapshotFreshness = .fresh,
    message: String? = nil,
    retryAvailableAt: Date? = nil
) -> SnapshotRefreshState {
    SnapshotRefreshState(
        content: content,
        freshness: freshness,
        message: message,
        retryAvailableAt: retryAvailableAt
    )
}

private let refreshNow = Date(timeIntervalSince1970: 1_785_549_720)
