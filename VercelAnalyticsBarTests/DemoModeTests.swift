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

        await model.restoreConnection()
        await model.load()

        #expect(model.accountState == .disconnected)
        guard case let .loaded(snapshot) = model.state else {
            Issue.record("Expected the demo fixture to load")
            return
        }
        #expect(snapshot == fixture)
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

        #expect(ideal.projectName == "example-site")
        #expect(ideal.topPages.first?.label == "/docs/getting-started")
        #expect(longValues.visitors.value > 1_000_000_000_000)
        #expect(longValues.projectName.count > 40)
        #expect(emptyBreakdowns.topPages.isEmpty)
        #expect(emptyBreakdowns.topReferrers.isEmpty)
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
