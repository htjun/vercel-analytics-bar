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
}

enum AnalyticsBreakdownListIntro {
    static let rowDuration = 0.22
    static let rowDelay = 0.04

    static func animation(for index: Int) -> Animation {
        .easeOut(duration: rowDuration)
            .delay(Double(index) * rowDelay)
    }
}

struct StaggeredBreakdownRows<RowContent: View>: View {
    let rows: [VercelAnalyticsBreakdown]
    let selection: AnalyticsBreakdownSelection
    let playback: BreakdownListIntroPlayback?
    @ViewBuilder let rowContent: (VercelAnalyticsBreakdown) -> RowContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasRevealed = false
    @State private var startsHidden: Bool

    init(
        rows: [VercelAnalyticsBreakdown],
        selection: AnalyticsBreakdownSelection,
        playback: BreakdownListIntroPlayback?,
        @ViewBuilder rowContent: @escaping (VercelAnalyticsBreakdown) -> RowContent
    ) {
        self.rows = rows
        self.selection = selection
        self.playback = playback
        self.rowContent = rowContent
        _startsHidden = State(initialValue: playback?.isEligible(selection) ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                rowContent(row)
                    .opacity(rowOpacity)
                    .animation(AnalyticsBreakdownListIntro.animation(for: index), value: hasRevealed)
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
        guard startsHidden, let playback else {
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
