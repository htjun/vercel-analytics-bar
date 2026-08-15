import Foundation
import Testing
@testable import VercelAnalyticsBar

@Suite("Chart intro animation")
struct ChartIntroAnimationTests {
    @MainActor
    @Test func playbackRunsOnceForTheApplication() {
        let gate = ChartIntroPlaybackGate()

        #expect(gate.isEligible(for: .application))
        #expect(gate.claim(.application))
        #expect(!gate.isEligible(for: .application))
        #expect(!gate.claim(.application))
    }

    @MainActor
    @Test func playbackRunsOnceForEachPanelSession() {
        let gate = ChartIntroPlaybackGate()
        let firstSession = UUID()
        let secondSession = UUID()

        #expect(gate.claim(.session(firstSession)))
        #expect(!gate.claim(.session(firstSession)))
        #expect(gate.claim(.session(secondSession)))
    }

    @Test func defaultsMatchThePlannedSequence() {
        let style = ChartStyle.default

        #expect(style.chartIntroAnimationEnabled)
        #expect(style.lineRevealDuration == 0.8)
        #expect(style.lineRevealEasing == .easeOut)
        #expect(style.areaFadeDuration == 0.3)
        #expect(style.areaFadeDelay == 0.05)
    }

    @Test func decodingRejectsInvalidAnimationValues() throws {
        let invalidValues: [String: Any] = [
            "lineRevealDuration": 3.01,
            "lineRevealEasing": "spring",
            "areaFadeDuration": 2.01,
            "areaFadeDelay": -0.01,
        ]

        for (field, value) in invalidValues {
            var object = try encodedDefaultObject()
            object[field] = value
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(ChartStyle.self, from: data)
            }
        }
    }

    private func encodedDefaultObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(ChartStyle.default)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
