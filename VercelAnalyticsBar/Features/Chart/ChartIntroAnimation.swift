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

@MainActor
@Observable
final class ChartIntroAnimator {
    private var lineRevealProgress = 1.0
    private var areaRevealProgress = 1.0
    private var hasResolvedPlayback = false

    func effectiveLineProgress(
        style: ChartStyle,
        reduceMotion: Bool,
        playback: ChartIntroPlayback?
    ) -> Double {
        effectiveProgress(
            lineRevealProgress,
            style: style,
            reduceMotion: reduceMotion,
            playback: playback
        )
    }

    func effectiveAreaProgress(
        style: ChartStyle,
        reduceMotion: Bool,
        playback: ChartIntroPlayback?
    ) -> Double {
        effectiveProgress(
            areaRevealProgress,
            style: style,
            reduceMotion: reduceMotion,
            playback: playback
        )
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

        updateWithoutAnimation(lineProgress: 0, areaProgress: 0)
        await Task.yield()
        guard !Task.isCancelled else { return }

        withAnimation(style.lineRevealEasing.animation(duration: style.lineRevealDuration)) {
            lineRevealProgress = 1
        }

        do {
            try await Task.sleep(for: .seconds(style.lineRevealDuration + style.areaFadeDelay))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: style.areaFadeDuration)) {
            areaRevealProgress = 1
        }
    }

    func finish() {
        updateWithoutAnimation(lineProgress: 1, areaProgress: 1)
    }

    private func effectiveProgress(
        _ progress: Double,
        style: ChartStyle,
        reduceMotion: Bool,
        playback: ChartIntroPlayback?
    ) -> Double {
        guard style.chartIntroAnimationEnabled, !reduceMotion, let playback else { return 1 }
        return hasResolvedPlayback || !playback.isEligible() ? progress : 0
    }

    private func updateWithoutAnimation(lineProgress: Double, areaProgress: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            lineRevealProgress = lineProgress
            areaRevealProgress = areaProgress
            hasResolvedPlayback = true
        }
    }
}

private extension ChartAnimationEasing {
    func animation(duration: TimeInterval) -> Animation {
        switch self {
        case .linear: .linear(duration: duration)
        case .easeIn: .easeIn(duration: duration)
        case .easeOut: .easeOut(duration: duration)
        case .easeInOut: .easeInOut(duration: duration)
        }
    }
}
