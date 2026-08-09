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
