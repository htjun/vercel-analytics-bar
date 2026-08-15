import Observation
import SwiftUI

enum ChartIntroPlaybackScope: Hashable {
    case application
    case session(UUID)
}

@MainActor
final class ChartIntroPlaybackGate {
    private var hasPlayedForApplication = false
    private var playedSession: UUID?

    func isEligible(for scope: ChartIntroPlaybackScope) -> Bool {
        switch scope {
        case .application:
            !hasPlayedForApplication
        case let .session(sessionID):
            playedSession != sessionID
        }
    }

    func claim(_ scope: ChartIntroPlaybackScope) -> Bool {
        guard isEligible(for: scope) else { return false }

        switch scope {
        case .application:
            hasPlayedForApplication = true
        case let .session(sessionID):
            playedSession = sessionID
        }
        return true
    }
}

struct ChartIntroPlayback {
    enum PlaybackID: Hashable {
        case panel(UUID)
        case inspector(Int)
    }

    let id: PlaybackID
    let isEligible: @MainActor () -> Bool
    let claim: @MainActor () -> Bool

    @MainActor
    static func panel(
        sessionID: UUID,
        scope: ChartIntroPlaybackScope,
        gate: ChartIntroPlaybackGate
    ) -> ChartIntroPlayback {
        ChartIntroPlayback(
            id: .panel(sessionID),
            isEligible: { gate.isEligible(for: scope) },
            claim: { gate.claim(scope) }
        )
    }

    static func inspector(replayToken: Int) -> ChartIntroPlayback {
        ChartIntroPlayback(
            id: .inspector(replayToken),
            isEligible: { true },
            claim: { true }
        )
    }
}

struct ChartIntroAnimationValues: Equatable {
    static let hidden = ChartIntroAnimationValues(lineProgress: 0, areaProgress: 0)
    static let complete = ChartIntroAnimationValues(lineProgress: 1, areaProgress: 1)

    let lineProgress: Double
    let areaProgress: Double
}

struct ChartIntroTimeline {
    let lineDuration: TimeInterval
    let lineEasing: ChartAnimationEasing
    let fillDuration: TimeInterval
    let fillDelay: TimeInterval

    init(style: ChartStyle) {
        lineDuration = style.lineRevealDuration
        lineEasing = style.lineRevealEasing
        fillDuration = style.areaFadeDuration
        fillDelay = style.areaFadeDelay
    }

    var duration: TimeInterval {
        lineDuration + fillDelay + fillDuration
    }

    func values(at elapsedTime: TimeInterval) -> ChartIntroAnimationValues {
        let lineFraction = normalized(elapsedTime / lineDuration)
        let fillStart = lineDuration + fillDelay
        let fillFraction = normalized((elapsedTime - fillStart) / fillDuration)

        return ChartIntroAnimationValues(
            lineProgress: lineEasing.unitCurve.value(at: lineFraction),
            areaProgress: UnitCurve.easeOut.value(at: fillFraction)
        )
    }

    private func normalized(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

@MainActor
@Observable
final class ChartIntroAnimator {
    enum State {
        case pending
        case running(timeline: ChartIntroTimeline, startUptime: TimeInterval)
        case complete
    }

    private(set) var state = State.pending

    func initialValues(
        style: ChartStyle,
        reduceMotion: Bool,
        playback: ChartIntroPlayback?
    ) -> ChartIntroAnimationValues {
        guard style.chartIntroAnimationEnabled,
              !reduceMotion,
              let playback,
              playback.isEligible()
        else {
            return .complete
        }
        return .hidden
    }

    func run(
        style: ChartStyle,
        reduceMotion: Bool,
        playback: ChartIntroPlayback?
    ) async {
        guard let playback else {
            finish()
            return
        }
        let shouldAnimate = playback.claim()
        guard style.chartIntroAnimationEnabled, !reduceMotion, shouldAnimate else {
            finish()
            return
        }

        let timeline = ChartIntroTimeline(style: style)
        let startUptime = ProcessInfo.processInfo.systemUptime
        state = .running(timeline: timeline, startUptime: startUptime)

        do {
            try await Task.sleep(for: .seconds(timeline.duration))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        finish()
    }

    func finish() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            state = .complete
        }
    }
}

struct ChartIntroAnimationContainer<Content: View>: View {
    let style: ChartStyle
    let playback: ChartIntroPlayback?
    @ViewBuilder let content: (ChartIntroAnimationValues) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animator = ChartIntroAnimator()

    var body: some View {
        animatedContent
            .task {
                await animator.run(
                    style: style,
                    reduceMotion: reduceMotion,
                    playback: playback
                )
            }
            .onChange(of: reduceMotion) { _, isEnabled in
                if isEnabled {
                    animator.finish()
                }
            }
    }

    @ViewBuilder
    private var animatedContent: some View {
        switch animator.state {
        case .pending:
            content(animator.initialValues(
                style: style,
                reduceMotion: reduceMotion,
                playback: playback
            ))
        case let .running(timeline, startUptime):
            TimelineView(.animation) { _ in
                content(timeline.values(
                    at: ProcessInfo.processInfo.systemUptime - startUptime
                ))
            }
        case .complete:
            content(.complete)
        }
    }
}

private extension ChartAnimationEasing {
    var unitCurve: UnitCurve {
        switch self {
        case .linear: .linear
        case .easeIn: .easeIn
        case .easeOut: .easeOut
        case .easeInOut: .easeInOut
        }
    }
}
