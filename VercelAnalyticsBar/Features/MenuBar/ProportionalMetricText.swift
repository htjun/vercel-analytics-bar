import CoreText
import SwiftUI

struct ProportionalMetricToken: Equatable, Identifiable {
    enum TokenID: Hashable {
        case digit(place: Int)
        case grouping(digitsToRight: Int)
        case literal(positionFromRight: Int)
    }

    let id: TokenID
    let character: Character

    var text: String {
        String(character)
    }

    static func make(for value: Int) -> [ProportionalMetricToken] {
        make(for: ProportionalMetricText.format(value))
    }

    static func make(for formatted: String) -> [ProportionalMetricToken] {
        var digitPlace = 0
        var reversedTokens: [ProportionalMetricToken] = []

        for character in formatted.reversed() {
            let id: TokenID
            if character.isNumber {
                id = .digit(place: digitPlace)
                digitPlace += 1
            } else if character == "," {
                id = .grouping(digitsToRight: digitPlace)
            } else {
                id = .literal(positionFromRight: reversedTokens.count)
            }
            reversedTokens.append(ProportionalMetricToken(id: id, character: character))
        }

        return reversedTokens.reversed()
    }
}

@MainActor
enum ProportionalMetricLayout {
    static func width(
        for token: ProportionalMetricToken,
        style: NumberStyle = .default
    ) -> CGFloat {
        width(for: token.text, style: style)
    }

    static func naturalWidth(
        for tokens: [ProportionalMetricToken],
        style: NumberStyle = .default
    ) -> CGFloat {
        tokens.reduce(0) { $0 + width(for: $1, style: style) }
            + trackingWidth(for: tokens, style: style)
    }

    static func reservedWidth(
        for tokens: [ProportionalMetricToken],
        style: NumberStyle = .default
    ) -> CGFloat {
        let maximumDigitWidth = (0 ... 9)
            .map { width(for: String($0), style: style) }
        .max() ?? 0

        return tokens.reduce(0) { width, token in
            switch token.id {
            case .digit:
                width + maximumDigitWidth
            case .grouping, .literal:
                width + self.width(for: token, style: style)
            }
        } + trackingWidth(for: tokens, style: style)
    }

    static func leadingOffsets(
        for tokens: [ProportionalMetricToken],
        style: NumberStyle = .default
    ) -> [ProportionalMetricToken.TokenID: CGFloat] {
        var offset: CGFloat = 0
        var offsets: [ProportionalMetricToken.TokenID: CGFloat] = [:]

        for (index, token) in tokens.enumerated() {
            offsets[token.id] = offset
            offset += width(for: token, style: style)
            if index < tokens.count - 1 {
                offset += CGFloat(style.tracking)
            }
        }

        return offsets
    }

    private static func width(for text: String, style: NumberStyle) -> CGFloat {
        let attributedText = NSAttributedString(
            string: text,
            attributes: [.font: style.nsFont]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func trackingWidth(
        for tokens: [ProportionalMetricToken],
        style: NumberStyle
    ) -> CGFloat {
        CGFloat(max(tokens.count - 1, 0)) * CGFloat(style.tracking)
    }
}

struct ProportionalMetricText: View {
    static let frameWidth: CGFloat = 114
    static let availableWidth: CGFloat = 160
    static let frameHeight: CGFloat = 58
    static let minimumScale: CGFloat = 0.7

    let value: Int
    let style: NumberStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderedValue: Int
    @State private var countsDown = false

    init(value: Int, style: NumberStyle = .default) {
        self.value = value
        self.style = style
        _renderedValue = State(initialValue: value)
    }

    var body: some View {
        Group {
            if reduceMotion {
                staticText
            } else {
                animatedText
            }
        }
        .frame(width: Self.frameWidth, height: Self.frameHeight, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.format(value))
        .help(Self.format(value))
        .onChange(of: value) { _, newValue in
            updateRenderedValue(newValue, animated: !reduceMotion)
        }
        .onChange(of: reduceMotion) { _, _ in
            updateRenderedValue(value, animated: false)
        }
    }

    private var staticText: some View {
        let displayText = Self.displayText(for: value, style: style)
        let tokens = ProportionalMetricToken.make(for: displayText)

        return Text(displayText)
            .font(style.font)
            .tracking(style.tracking)
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(Self.scale(for: tokens, style: style), anchor: .topLeading)
            .frame(width: Self.availableWidth, height: Self.frameHeight, alignment: .topLeading)
            .clipped()
    }

    private var animatedText: some View {
        let displayText = Self.displayText(for: renderedValue, style: style)
        let tokens = ProportionalMetricToken.make(for: displayText)

        return HStack(alignment: .firstTextBaseline, spacing: CGFloat(style.tracking)) {
            ForEach(tokens) { token in
                tokenText(token)
            }
        }
        .fixedSize()
        .scaleEffect(Self.scale(for: tokens, style: style), anchor: .topLeading)
        .frame(width: Self.availableWidth, height: Self.frameHeight, alignment: .topLeading)
        .clipped()
    }

    private func tokenText(_ token: ProportionalMetricToken) -> some View {
        let width = ProportionalMetricLayout.width(for: token, style: style)

        return Text(token.text)
            .font(style.font)
            .tracking(style.tracking)
            .contentTransition(.numericText(countsDown: countsDown))
            .frame(width: width, height: Self.frameHeight, alignment: .topLeading)
            .clipped()
            .transition(.proportionalMetricToken(width: width))
    }

    private func updateRenderedValue(_ newValue: Int, animated: Bool) {
        countsDown = Self.rollsDown(from: renderedValue, to: newValue)
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                renderedValue = newValue
            }
            return
        }

        withAnimation(style.animation) {
            renderedValue = newValue
        }
    }

    nonisolated static func format(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    nonisolated static func rollsDown(from oldValue: Int, to newValue: Int) -> Bool {
        newValue < oldValue
    }

    static func displayText(for value: Int, style: NumberStyle = .default) -> String {
        let fullText = format(value)
        let fullTokens = ProportionalMetricToken.make(for: fullText)
        let minimumScaleWidth = availableWidth / minimumScale

        guard ProportionalMetricLayout.reservedWidth(for: fullTokens, style: style) > minimumScaleWidth else {
            return fullText
        }

        return AnalyticsCountFormatter.compact(value)
    }

    static func scale(for tokens: [ProportionalMetricToken], style: NumberStyle = .default) -> CGFloat {
        let reservedWidth = ProportionalMetricLayout.reservedWidth(for: tokens, style: style)
        return max(Self.minimumScale, min(1, Self.availableWidth / max(reservedWidth, 1)))
    }
}

private struct ProportionalMetricTokenTransition: ViewModifier {
    let width: CGFloat
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width * progress, alignment: .trailing)
            .opacity(progress)
            .clipped()
    }
}

private extension AnyTransition {
    static func proportionalMetricToken(width: CGFloat) -> AnyTransition {
        .modifier(
            active: ProportionalMetricTokenTransition(width: width, progress: 0),
            identity: ProportionalMetricTokenTransition(width: width, progress: 1)
        )
    }
}
