import Observation

@MainActor
@Observable
final class ChartStyleStore {
    private(set) var style: ChartStyle

    init(style: ChartStyle = .default) {
        self.style = style
    }

    func update(_ style: ChartStyle) {
        guard style != self.style else { return }
        self.style = style
    }

    func reset() {
        update(.default)
    }
}

struct ChartIntroAnimation: Equatable {
    let isEnabled: Bool
    let lineDuration: Double
    let lineEasing: ChartAnimationEasing
    let fillDuration: Double
    let fillDelay: Double
}

extension ChartStyle {
    var introAnimation: ChartIntroAnimation {
        ChartIntroAnimation(
            isEnabled: chartIntroAnimationEnabled,
            lineDuration: lineRevealDuration,
            lineEasing: lineRevealEasing,
            fillDuration: areaFadeDuration,
            fillDelay: areaFadeDelay
        )
    }
}
