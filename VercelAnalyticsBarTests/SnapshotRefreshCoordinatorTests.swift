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
    let request = refreshRequest()

    let preparation = driver.coordinator.prepare(request)
    #expect(preparation.cachedSnapshot == cachedSnapshot)
    #expect(preparation.freshness == .stale)
    #expect(preparation.shouldRequestLiveSnapshot)

    let refresh = driver.start(request)
    await driver.provider.waitUntilRequested()
    let liveSnapshot = refreshFixture(visitors: 150, refreshedAt: refreshNow)
    await driver.provider.succeed(with: liveSnapshot)
    await refresh.value

    #expect(driver.events == [
        .cached(cachedSnapshot, freshness: .stale),
        .succeeded(liveSnapshot),
    ])
    #expect(cacheStore.entries == [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: liveSnapshot),
    ])
}

@MainActor
@Test func snapshotRefreshCoordinatorCoalescesConcurrentRequests() async {
    let driver = SnapshotRefreshTestDriver()
    let request = refreshRequest(trigger: .periodic)

    let firstRefresh = driver.start(request)
    await driver.provider.waitUntilRequested()
    let secondRefresh = driver.start(request)

    #expect(await driver.provider.requestedRanges == [.last7Days])

    let snapshot = refreshFixture()
    await driver.provider.succeed(with: snapshot)
    await firstRefresh.value
    await secondRefresh.value

    #expect(await driver.provider.requestedRanges == [.last7Days])
    #expect(driver.events.count(where: { $0 == .succeeded(snapshot) }) == 1)
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
    #expect(driver.events.contains(.succeeded(alphaSnapshot)) == false)

    let betaSnapshot = refreshFixture(projectName: "Beta", visitors: 300)
    await betaProvider.succeed(with: betaSnapshot)
    await betaRefresh.value
    #expect(driver.events.last == .succeeded(betaSnapshot))
}

@MainActor
@Test func snapshotRefreshCoordinatorKeepsCacheOnTransientFailure() async {
    let snapshot = refreshFixture()
    let driver = SnapshotRefreshTestDriver(cacheEntries: [
        SnapshotCacheEntry(projectID: "project-alpha", snapshot: snapshot),
    ])
    let transientError = VercelAPIError.transient(status: 503, requestID: "fixture-request-id")

    await failRefresh(driver, request: refreshRequest(trigger: .periodic), error: transientError)

    #expect(driver.events.last == .recoverableFailure(
        snapshot,
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

    #expect(driver.events.contains(.succeeded(snapshot)) == false)
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
    #expect(driver.events.last == .recoverableFailure(
        snapshot,
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
    #expect(driver.events.last == .blocked(
        message: "Retry limit reached. Wait before trying again.",
        retryAvailableAt: nil
    ))

    clock.advance(by: 300)
    let resetRetry = driver.start(request)
    await driver.provider.waitUntilRequested()
    await driver.provider.succeed(with: snapshot)
    await resetRetry.value
    #expect(await driver.provider.requestedRanges.count == requestCountBeforeLimit + 1)
    #expect(driver.events.last == .succeeded(snapshot))
}

@MainActor
private final class SnapshotRefreshTestDriver {
    let provider: ControlledSnapshotProvider
    let coordinator: SnapshotRefreshCoordinator
    private(set) var events: [SnapshotRefreshEvent] = []

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
            showLoading: showLoading,
            eventHandler: { [weak self] in self?.events.append($0) }
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

private let refreshNow = Date(timeIntervalSince1970: 1_785_549_720)
