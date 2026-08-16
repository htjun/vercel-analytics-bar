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

    @MainActor
    @Test func animatorClaimsEachPlaybackOnlyOnce() async {
        var claimCount = 0
        let playback = ChartIntroPlayback(
            id: .editor(0),
            isEligible: { true },
            claim: {
                claimCount += 1
                return true
            }
        )
        let animator = ChartIntroAnimator()

        await animator.run(style: .default, reduceMotion: true, playback: playback)
        await animator.run(style: .default, reduceMotion: true, playback: playback)

        #expect(claimCount == 1)
    }

    @Test func defaultsMatchThePlannedSequence() {
        let style = ChartStyle.default

        #expect(style.chartIntroAnimationEnabled)
        #expect(style.lineRevealDuration == 1)
        #expect(style.lineRevealEasing == .easeOut)
        #expect(style.areaFadeDuration == 1.25)
        #expect(style.areaFadeDelay == -0.5)
    }

    @Test func timelineStartsHiddenAndFinishesComplete() {
        let timeline = ChartIntroTimeline(style: .default)

        #expect(timeline.values(at: -0.1) == .hidden)
        #expect(timeline.values(at: 0) == .hidden)
        #expect(timeline.values(at: timeline.duration) == .complete)
        #expect(timeline.values(at: timeline.duration + 1) == .complete)
    }

    @Test func timelineRevealsLineBeforeArea() {
        let timeline = ChartIntroTimeline(style: .default)
        let lineMidpoint = timeline.values(at: timeline.lineDuration / 2)
        let fillStart = timeline.lineDuration + timeline.fillDelay

        #expect(lineMidpoint.lineProgress > 0.5)
        #expect(lineMidpoint.lineProgress < 1)
        #expect(lineMidpoint.areaProgress == 0)
        #expect(timeline.values(at: timeline.lineDuration).lineProgress == 1)
        #expect(timeline.values(at: fillStart).areaProgress == 0)
    }

    @Test func timelineFadesAreaAfterConfiguredDelay() {
        let timeline = ChartIntroTimeline(style: .default)
        let fillStart = timeline.lineDuration + timeline.fillDelay
        let fillMidpoint = timeline.values(at: fillStart + timeline.fillDuration / 2)

        #expect(fillMidpoint.lineProgress == 1)
        #expect(fillMidpoint.areaProgress > 0.5)
        #expect(fillMidpoint.areaProgress < 1)
    }

    @Test func negativeFillDelayStartsAreaBeforeLineCompletes() throws {
        var object = try encodedDefaultObject()
        object["areaFadeDelay"] = -0.5
        let data = try JSONSerialization.data(withJSONObject: object)
        let style = try JSONDecoder().decode(ChartStyle.self, from: data)
        let timeline = ChartIntroTimeline(style: style)
        let overlappingValues = timeline.values(at: 0.75)

        #expect(overlappingValues.lineProgress < 1)
        #expect(overlappingValues.areaProgress > 0)
    }

    @Test func decodingRejectsInvalidAnimationValues() throws {
        let invalidValues: [String: Any] = [
            "lineRevealDuration": 3.01,
            "lineRevealEasing": "spring",
            "areaFadeDuration": 2.01,
            "areaFadeDelay": -1.01,
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
