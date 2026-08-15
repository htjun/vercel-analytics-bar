import Foundation
import Testing
@testable import VercelAnalyticsBar
import VercelAnalyticsCore

@Suite("Demo mode")
struct DemoModeTests {
    @Test func fixtureDecoderAcceptsHumanReadableDates() throws {
        let snapshot = try DemoFixtureLoader.decode(Self.fixtureData)

        #expect(snapshot.projectName == "Screenshot Project")
        #expect(snapshot.range == .last30Days)
        #expect(snapshot.visitors.value == 987_654_321)
        #expect(snapshot.series.count == 2)
        #expect(snapshot.refreshedAt == ISO8601DateFormatter().date(from: "2026-08-11T00:00:00Z"))
    }

    @Test func fixtureLoaderReportsMissingUnreadableAndInvalidFiles() {
        #expect(throws: DemoFixtureError.missing) {
            try DemoFixtureLoader.load(from: nil)
        }
        #expect(throws: DemoFixtureError.unreadable) {
            try DemoFixtureLoader.load(from: URL(fileURLWithPath: "/missing/demo-fixture.json"))
        }
        #expect(throws: DemoFixtureError.invalid) {
            try DemoFixtureLoader.decode(Data(#"{"projectName":"Incomplete"}"#.utf8))
        }
    }

    @Test func providerReflectsTheRequestedRange() async throws {
        let fixture = try DemoFixtureLoader.decode(Self.fixtureData)
        let provider = DemoAnalyticsSnapshotProvider(snapshot: fixture)

        let snapshot = try await provider.snapshot(for: .last24Hours)

        #expect(provider.initialRange == .last30Days)
        #expect(snapshot.range == .last24Hours)
        #expect(snapshot.projectName == fixture.projectName)
        #expect(snapshot.visitors == fixture.visitors)
    }

    @MainActor
    @Test func modelLoadsThroughTheFixtureProviderWithoutLiveFactories() async throws {
        let fixture = try DemoFixtureLoader.decode(Self.fixtureData)
        let model = DemoAppModelFactory.makeModel(
            provider: DemoAnalyticsSnapshotProvider(snapshot: fixture),
            initialRange: fixture.range
        )

        #expect(model.selectedRange == .last30Days)
        #expect(model.projectProviderFactory == nil)
        #expect(model.analyticsProviderFactory == nil)
        #expect(model.launchAtLoginStatus == .unavailable)
        #expect(model.selectedProjects(matching: "").count == 5)
        #expect(model.currentProject?.name == "node-storefront")

        await model.restoreConnection()
        await model.load()

        #expect(model.accountState == .disconnected)
        guard case let .loaded(snapshot) = model.state else {
            Issue.record("Expected the demo fixture to load")
            return
        }
        #expect(snapshot == fixture)

        await model.selectProject("checkout-worker")
        #expect(model.currentProject?.name == "checkout-worker")
        guard case let .loaded(switchedSnapshot) = model.state else {
            Issue.record("Expected the demo fixture to remain loaded after switching projects")
            return
        }
        #expect(switchedSnapshot == fixture)
    }

    @MainActor
    @Test func invalidFixtureBecomesAnUnavailableState() async {
        let model = DemoAppModelFactory.makeModel(
            provider: DemoAnalyticsSnapshotProvider(error: .invalid),
            initialRange: .last7Days
        )

        await model.load()

        #expect(model.state == .failed("The demo fixture contains invalid analytics data."))
    }

    @MainActor
    @Test func loadedDemoSnapshotIsReusedWhenThePanelReopens() async throws {
        let fixture = try DemoFixtureLoader.decode(Self.fixtureData)
        let provider = ControlledSnapshotProvider()
        let model = DemoAppModelFactory.makeModel(
            provider: provider,
            initialRange: fixture.range
        )

        let initialLoad = Task {
            await model.loadDemoSnapshotIfNeeded()
        }
        await provider.waitUntilRequested()
        await provider.succeed(with: fixture)
        await initialLoad.value

        await model.loadDemoSnapshotIfNeeded()

        #expect(await provider.requestedRanges == [fixture.range])
        #expect(model.state == .loaded(fixture))
    }

    @Test(arguments: ["ideal", "long-values", "empty-breakdowns"])
    func committedFixtureDecodes(_ fixtureName: String) throws {
        let snapshot = try DemoFixtureLoader.load(
            from: Self.fixtureRoot.appendingPathComponent("\(fixtureName).json")
        )

        #expect(!snapshot.projectName.isEmpty)
        #expect(!snapshot.series.isEmpty)
    }

    @Test func committedScenariosExerciseThePlannedEdges() throws {
        let ideal = try DemoFixtureLoader.load(
            from: Self.fixtureRoot.appendingPathComponent("ideal.json")
        )
        let longValues = try DemoFixtureLoader.load(
            from: Self.fixtureRoot.appendingPathComponent("long-values.json")
        )
        let emptyBreakdowns = try DemoFixtureLoader.load(
            from: Self.fixtureRoot.appendingPathComponent("empty-breakdowns.json")
        )

        #expect(ideal.projectName == "node-storefront")
        #expect(ideal.visitors.value == 802)
        #expect(ideal.visitors.previousValue == 716)
        #expect(ideal.pageViews.value == 3146)
        #expect(ideal.pageViews.previousValue == 3277)
        #expect(ideal.range == .last24Hours)
        #expect(ideal.series.count == 24)
        #expect(ideal.series.map(\.pageViews).reduce(0, +) == ideal.pageViews.value)
        #expect(ideal.last24HoursVisitors == 802)
        #expect(ideal.topPages.first?.label == "/dashboard")
        #expect(longValues.visitors.value > 1_000_000_000_000)
        #expect(longValues.projectName.count > 40)
        #expect(emptyBreakdowns.topPages.isEmpty)
        #expect(emptyBreakdowns.topReferrers.isEmpty)
    }

    @MainActor
    @Test func metricTickerAdvancesOnceAfterOneSecondAndAgainFiveSecondsLater() async throws {
        let sleeper = DemoTickerTestSleeper()
        let ticker = DemoMetricTicker(sleep: { duration in
            try await sleeper.sleep(for: duration)
        })

        ticker.start()
        let firstDuration = try await sleeper.waitForPendingSleep(after: 0)
        #expect(firstDuration == .seconds(1))
        #expect(ticker.offsets == .zero)

        await sleeper.resumeNext()
        try await waitUntil { ticker.offsets == DemoMetricOffsets(visitors: 7, pageViews: 13) }
        let secondDuration = try await sleeper.waitForPendingSleep(after: 1)
        #expect(secondDuration == .seconds(5))

        await sleeper.resumeNext()
        try await waitUntil {
            ticker.offsets == DemoMetricOffsets(visitors: 14, pageViews: 26) &&
                !ticker.isRunning
        }
        let pendingCount = await sleeper.pendingCount
        #expect(pendingCount == 0)

        ticker.stop()
        #expect(ticker.offsets == .zero)
        #expect(!ticker.isRunning)
    }

    @MainActor
    @Test func metricTickerRestartCancelsThePreviousLoopAndResets() async throws {
        let sleeper = DemoTickerTestSleeper()
        let ticker = DemoMetricTicker(sleep: { duration in
            try await sleeper.sleep(for: duration)
        })

        ticker.start()
        _ = try await sleeper.waitForPendingSleep(after: 0)
        ticker.start()
        _ = try await sleeper.waitForPendingSleep(after: 1)
        try await sleeper.waitForPendingCount(1)
        let pendingCount = await sleeper.pendingCount
        #expect(ticker.offsets == .zero)
        #expect(pendingCount == 1)

        await sleeper.resumeNext()
        try await waitUntil { ticker.offsets == DemoMetricOffsets(visitors: 7, pageViews: 13) }
        ticker.stop()
    }

    @Test func metricOffsetsSaturateInsteadOfOverflowing() {
        let offsets = DemoMetricOffsets(visitors: Int.max - 3, pageViews: Int.max - 2)

        #expect(offsets.advanced() == DemoMetricOffsets(visitors: .max, pageViews: .max))
    }

    @Test func metricOffsetsOnlyChangeHeadlineValues() {
        let base = AnalyticsCardPresentation.sampleFixture
        let adjusted = base.applyingDemoOffsets(DemoMetricOffsets(visitors: 7, pageViews: 13))

        #expect(adjusted.visitors.value == base.visitors.value + 7)
        #expect(adjusted.pageViews.value == base.pageViews.value + 13)
        #expect(adjusted.visitors.comparisonText == base.visitors.comparisonText)
        #expect(adjusted.pageViews.comparisonText == base.pageViews.comparisonText)
        #expect(adjusted.series == base.series)
        #expect(adjusted.topPages == base.topPages)
        #expect(adjusted.topReferrers == base.topReferrers)
        #expect(adjusted.updatedText == base.updatedText)
    }

    @MainActor
    @Test func metricOffsetsAlsoChangeTheDemoMenuBarVisitorCount() async throws {
        let fixture = try DemoFixtureLoader.load(
            from: Self.fixtureRoot.appendingPathComponent("ideal.json")
        )
        let model = DemoAppModelFactory.makeModel(
            provider: DemoAnalyticsSnapshotProvider(snapshot: fixture),
            initialRange: fixture.range
        )
        await model.load()

        let offsets = DemoMetricOffsets(visitors: 7, pageViews: 13)

        #expect(model.abbreviatedVisitors(applyingDemoOffsets: offsets) == "809")
    }

    private static let fixtureRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("DemoFixtures", isDirectory: true)

    private static let fixtureData = Data(
        #"""
        {
          "projectName": "Screenshot Project",
          "range": "last30Days",
          "visitors": {
            "label": "Visitors",
            "value": 987654321,
            "previousValue": 876543210
          },
          "pageViews": {
            "label": "Page Views",
            "value": 1234567890,
            "previousValue": 1000000000
          },
          "series": [
            {
              "timestamp": "2026-08-10T00:00:00Z",
              "visitors": 120,
              "pageViews": 240
            },
            {
              "timestamp": "2026-08-11T00:00:00Z",
              "visitors": 160,
              "pageViews": 320
            }
          ],
          "topPages": [],
          "topReferrers": [],
          "last24HoursVisitors": 43210,
          "refreshedAt": "2026-08-11T00:00:00Z"
        }
        """#.utf8
    )
}

private actor DemoTickerTestSleeper {
    private struct PendingSleep {
        let id: UUID
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var pendingSleeps: [PendingSleep] = []
    private var registrationCount = 0

    var pendingCount: Int {
        pendingSleeps.count
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registrationCount += 1
                pendingSleeps.append(PendingSleep(
                    id: id,
                    duration: duration,
                    continuation: continuation
                ))
            }
        } onCancel: {
            Task {
                await self.cancel(id: id)
            }
        }
    }

    func waitForPendingSleep(after previousRegistrationCount: Int) async throws -> Duration {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if registrationCount > previousRegistrationCount, let pendingSleep = pendingSleeps.last {
                return pendingSleep.duration
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw DemoTickerTestError.timedOut
    }

    func waitForPendingCount(_ expectedCount: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if pendingSleeps.count == expectedCount { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw DemoTickerTestError.timedOut
    }

    func resumeNext() {
        guard !pendingSleeps.isEmpty else { return }
        pendingSleeps.removeFirst().continuation.resume()
    }

    private func cancel(id: UUID) {
        guard let index = pendingSleeps.firstIndex(where: { $0.id == id }) else { return }
        pendingSleeps.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

private enum DemoTickerTestError: Error {
    case timedOut
}

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw DemoTickerTestError.timedOut
}
