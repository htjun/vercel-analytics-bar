import SwiftUI
import VercelAnalyticsCore

enum BreakdownListIntroPlaybackScope: Hashable {
    case application
    case session(UUID)
}

@MainActor
final class BreakdownListIntroPlaybackGate {
    private var playedLists: Set<PlaybackKey> = []

    func isEligible(
        for selection: AnalyticsBreakdownSelection,
        scope: BreakdownListIntroPlaybackScope
    ) -> Bool {
        !playedLists.contains(PlaybackKey(selection: selection, scope: scope))
    }

    func claim(
        _ selection: AnalyticsBreakdownSelection,
        for scope: BreakdownListIntroPlaybackScope
    ) -> Bool {
        let key = PlaybackKey(selection: selection, scope: scope)
        guard !playedLists.contains(key) else { return false }
        playedLists.insert(key)
        return true
    }

    private struct PlaybackKey: Hashable {
        let selection: AnalyticsBreakdownSelection
        let scope: BreakdownListIntroPlaybackScope
    }
}

struct BreakdownListIntroPlayback {
    let isEligible: @MainActor (AnalyticsBreakdownSelection) -> Bool
    let claim: @MainActor (AnalyticsBreakdownSelection) -> Bool

    @MainActor
    static func panel(
        scope: BreakdownListIntroPlaybackScope,
        gate: BreakdownListIntroPlaybackGate
    ) -> BreakdownListIntroPlayback {
        BreakdownListIntroPlayback(
            isEligible: { selection in
                gate.isEligible(for: selection, scope: scope)
            },
            claim: { selection in
                gate.claim(selection, for: scope)
            }
        )
    }

    static func inspector() -> BreakdownListIntroPlayback {
        BreakdownListIntroPlayback(
            isEligible: { _ in true },
            claim: { _ in true }
        )
    }
}

enum AnalyticsBreakdownListIntro {
    static let rowDuration = 0.22
    static let rowDelay = 0.04

    static func animation(for index: Int, style: BreakdownListStyle) -> Animation {
        style.introAnimationEasing.animation(duration: style.rowAnimationDuration)
            .delay(Double(index) * style.rowAnimationDelay)
    }
}

struct StaggeredBreakdownRows<RowContent: View>: View {
    let rows: [VercelAnalyticsBreakdown]
    let selection: AnalyticsBreakdownSelection
    let style: BreakdownListStyle
    let playback: BreakdownListIntroPlayback?
    @ViewBuilder let rowContent: (VercelAnalyticsBreakdown) -> RowContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRevealed = false
    @State private var startsHidden: Bool

    init(
        rows: [VercelAnalyticsBreakdown],
        selection: AnalyticsBreakdownSelection,
        style: BreakdownListStyle,
        playback: BreakdownListIntroPlayback?,
        @ViewBuilder rowContent: @escaping (VercelAnalyticsBreakdown) -> RowContent
    ) {
        self.rows = rows
        self.selection = selection
        self.style = style
        self.playback = playback
        self.rowContent = rowContent
        _startsHidden = State(initialValue: style.introAnimationEnabled && (playback?.isEligible(selection) ?? false))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            ForEach(Array(rows.prefix(style.visibleRowCount).enumerated()), id: \.element.id) { index, row in
                rowContent(row)
                    .opacity(rowOpacity)
                    .animation(AnalyticsBreakdownListIntro.animation(for: index, style: style), value: hasRevealed)
            }
        }
        .onAppear(perform: revealIfNeeded)
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                hasRevealed = true
            }
        }
    }

    private var rowOpacity: Double {
        startsHidden && !hasRevealed && !reduceMotion ? 0 : 1
    }

    private func revealIfNeeded() {
        guard style.introAnimationEnabled, startsHidden, let playback else {
            hasRevealed = true
            return
        }

        guard playback.claim(selection), !reduceMotion else {
            hasRevealed = true
            return
        }

        hasRevealed = true
    }
}

private extension ChartAnimationEasing {
    func animation(duration: Double) -> Animation {
        switch self {
        case .linear:
            .linear(duration: duration)
        case .easeIn:
            .easeIn(duration: duration)
        case .easeOut:
            .easeOut(duration: duration)
        case .easeInOut:
            .easeInOut(duration: duration)
        }
    }
}
