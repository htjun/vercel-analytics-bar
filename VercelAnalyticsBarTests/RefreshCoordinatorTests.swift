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
