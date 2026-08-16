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

enum ComponentStyle: Equatable {
    case chart(ChartStyle)
    case list(BreakdownListStyle)
    case numbers(NumberStyle)

    var component: EditableComponent {
        switch self {
        case .chart:
            .chart
        case .list:
            .list
        case .numbers:
            .numbers
        }
    }
}

@MainActor
@Observable
final class ComponentStyleStore {
    private(set) var chartStyle: ChartStyle
    private(set) var listStyle: BreakdownListStyle
    private(set) var numberStyle: NumberStyle

    init(
        chartStyle: ChartStyle = .default,
        listStyle: BreakdownListStyle = .default,
        numberStyle: NumberStyle = .default
    ) {
        self.chartStyle = chartStyle
        self.listStyle = listStyle
        self.numberStyle = numberStyle
    }

    func style(for component: EditableComponent) -> ComponentStyle {
        switch component {
        case .chart:
            .chart(chartStyle)
        case .list:
            .list(listStyle)
        case .numbers:
            .numbers(numberStyle)
        }
    }

    func update(_ style: ComponentStyle) {
        switch style {
        case let .chart(style):
            guard style != chartStyle else { return }
            chartStyle = style
        case let .list(style):
            guard style != listStyle else { return }
            listStyle = style
        case let .numbers(style):
            guard style != numberStyle else { return }
            numberStyle = style
        }
    }

    func reset(_ component: EditableComponent) {
        switch component {
        case .chart:
            update(.chart(.default))
        case .list:
            update(.list(.default))
        case .numbers:
            update(.numbers(.default))
        }
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
