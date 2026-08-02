import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@MainActor
@Test func appModelSkipsPopoverRefreshForFreshCachedSnapshot() async {
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let provider = ControlledSnapshotProvider()
    let clock = MutableDateClock(date: Date(timeIntervalSince1970: 1_785_549_630))
    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(entries: [
            SnapshotCacheEntry(projectID: project.id, snapshot: snapshot),
        ]),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in provider },
        now: { clock.now() },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    await model.load()

    #expect(model.state == .loaded(snapshot))
    #expect(model.snapshotFreshness == .fresh)
    #expect(await provider.requestedRanges.isEmpty)
}

@MainActor
@Test func appModelCoalescesConcurrentRefreshes() async {
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let provider = ControlledSnapshotProvider()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in provider },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    let firstRefresh = Task { await model.load() }
    await provider.waitUntilRequested()
    let secondRefresh = Task { await model.load() }

    #expect(await provider.requestedRanges == [.last7Days])

    await provider.succeed(with: makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    ))
    await firstRefresh.value
    await secondRefresh.value

    #expect(await provider.requestedRanges == [.last7Days])
}

@MainActor
@Test func appModelKeepsCachedSnapshotWhenTransientRefreshFails() async {
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let provider = ControlledSnapshotProvider()
    let clock = MutableDateClock(date: Date(timeIntervalSince1970: 1_785_549_720))
    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in provider },
        now: { clock.now() },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    let initialRefresh = Task { await model.load() }
    await provider.waitUntilRequested()
    await provider.succeed(with: snapshot)
    await initialRefresh.value

    let failedRefresh = Task { await model.load() }
    await provider.waitUntilRequested()
    let transientError = VercelAPIError.transient(status: 503, requestID: "fixture-request-id")
    await provider.fail(with: transientError)
    await failedRefresh.value

    #expect(model.state == .loaded(snapshot))
    #expect(model.snapshotFreshness == .stale)
    #expect(model.refreshMessage == transientError.localizedDescription)
}

@MainActor
@Test func appModelAppliesRateLimitBackoffAndManualRetryLimit() async {
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let provider = ControlledSnapshotProvider()
    let clock = MutableDateClock(date: Date(timeIntervalSince1970: 1_785_549_720))
    let snapshot = makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    )
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in provider },
        now: { clock.now() },
        tokenValidator: { _ in }
    )
    let rateLimitError = VercelAPIError.rateLimited(
        metadata: VercelRateLimitMetadata(retryAfter: 1, requestID: "fixture-request-id")
    )

    await model.connect(token: "valid-token")
    let initialRefresh = Task { await model.load() }
    await provider.waitUntilRequested()
    await provider.succeed(with: snapshot)
    await initialRefresh.value

    let firstLimitedRefresh = Task { await model.retryRefresh() }
    await provider.waitUntilRequested()
    await provider.fail(with: rateLimitError)
    await firstLimitedRefresh.value
    #expect(model.retryAvailableAt == clock.now().addingTimeInterval(1))

    for _ in 0 ..< 3 {
        clock.advance(by: 2)
        let retry = Task { await model.retryRefresh() }
        await provider.waitUntilRequested()
        await provider.fail(with: rateLimitError)
        await retry.value
    }

    let requestCountBeforeLimit = await provider.requestedRanges.count
    clock.advance(by: 2)
    await model.retryRefresh()

    #expect(await provider.requestedRanges.count == requestCountBeforeLimit)
    #expect(model.refreshMessage == "Retry limit reached. Wait before trying again.")
}

@MainActor
@Test func appModelRefreshLoopUsesFiveMinuteInterval() async {
    let project = VercelProject(id: "project-alpha", name: "Alpha")
    let provider = ControlledSnapshotProvider()
    let sleeper = ManualRefreshSleeper()
    let model = AppModel(
        credentialStore: InMemoryCredentialStore(),
        accountDataStore: InMemoryAccountDataStore(),
        snapshotCacheStore: InMemorySnapshotCacheStore(),
        projectProviderFactory: { _ in FixtureProjectListingProvider(projects: [project]) },
        analyticsProviderFactory: { _, _ in provider },
        sleep: { duration in try await sleeper.sleep(for: duration) },
        tokenValidator: { _ in }
    )

    await model.connect(token: "valid-token")
    model.startRefreshLoop()
    await sleeper.waitUntilSleeping()
    #expect(await sleeper.durations == [.seconds(300)])

    await sleeper.release()
    await provider.waitUntilRequested()
    await provider.succeed(with: makeAnalyticsSnapshot(
        projectName: "Alpha",
        visitors: 100,
        pageViews: 200,
        last24HoursVisitors: 11,
        refreshedAt: Date(timeIntervalSince1970: 1_785_549_600)
    ))
    model.stopRefreshLoop()
    await sleeper.release()
}
