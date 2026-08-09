import SwiftUI

enum AnalyticsCardLayout {
    static let rootSize = CGSize(width: 400, height: 562)
    static let cardSize = CGSize(width: 384, height: 546)
    static let shellInset: CGFloat = 8
    static let outerCornerRadius: CGFloat = 32
    static let cardCornerRadius: CGFloat = 24
    static let chartFrame = CGRect(x: 8, y: 166, width: 368, height: 150)

    static let glassRimWidth: CGFloat = 0.5
    static let glassSpecularWidth: CGFloat = 1
    static let glassSpecularPeakOpacity: CGFloat = 0.8
    static let glassDispersionWidth: CGFloat = 0.5
    static let glassDispersionOffset: CGFloat = 0.5

    static let panelShadowOpacity: Float = 0.03
    static let panelShadowRadius: CGFloat = 12
    static let panelShadowOffset = CGSize(width: 0, height: -2)
    static let panelShadowPadding: CGFloat = 16
    static let panelShadowWindowSize = CGSize(
        width: rootSize.width + panelShadowPadding * 2,
        height: rootSize.height + panelShadowPadding * 2
    )
}

enum AnalyticsGlassAppearance: Equatable {
    case standard
    case reducedTransparency

    static func resolve(reduceTransparency: Bool) -> AnalyticsGlassAppearance {
        reduceTransparency ? .reducedTransparency : .standard
    }

    var showsDispersion: Bool {
        self == .standard
    }

    var usesOpaqueBackground: Bool {
        self == .reducedTransparency
    }
}

struct AnalyticsGlassEdgeArtwork: View {
    let appearance: AnalyticsGlassAppearance

    var body: some View {
        ZStack {
            if appearance.usesOpaqueBackground {
                outerShape
                    .fill(AnalyticsCardColors.reducedTransparencyShell)

                outerShape
                    .strokeBorder(
                        AnalyticsCardColors.reducedTransparencyOutline,
                        lineWidth: AnalyticsCardLayout.glassSpecularWidth
                    )
            } else {
                dispersionFringes

                outerShape
                    .strokeBorder(
                        AnalyticsCardColors.glassRim,
                        lineWidth: AnalyticsCardLayout.glassRimWidth
                    )

                outerShape
                    .strokeBorder(
                        specularGradient,
                        lineWidth: AnalyticsCardLayout.glassSpecularWidth
                    )
            }
        }
        .frame(
            width: AnalyticsCardLayout.rootSize.width,
            height: AnalyticsCardLayout.rootSize.height
        )
        .clipShape(outerShape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var outerShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AnalyticsCardLayout.outerCornerRadius,
            style: .continuous
        )
    }

    @ViewBuilder
    private var dispersionFringes: some View {
        if appearance.showsDispersion {
            outerShape
                .strokeBorder(
                    AnalyticsCardColors.glassCyanFringe,
                    lineWidth: AnalyticsCardLayout.glassDispersionWidth
                )
                .offset(
                    x: AnalyticsCardLayout.glassDispersionOffset,
                    y: -AnalyticsCardLayout.glassDispersionOffset
                )

            outerShape
                .strokeBorder(
                    AnalyticsCardColors.glassWarmFringe,
                    lineWidth: AnalyticsCardLayout.glassDispersionWidth
                )
                .offset(
                    x: -AnalyticsCardLayout.glassDispersionOffset,
                    y: AnalyticsCardLayout.glassDispersionOffset
                )
        }
    }

    private var specularGradient: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .white.opacity(AnalyticsCardLayout.glassSpecularPeakOpacity), location: 0),
                .init(color: .white.opacity(0.18), location: 0.025),
                .init(color: .white.opacity(0.06), location: 0.09),
                .init(color: .white.opacity(0.10), location: 0.50),
                .init(color: .white.opacity(0.35), location: 0.975),
                .init(color: .white.opacity(AnalyticsCardLayout.glassSpecularPeakOpacity), location: 1),
            ],
            center: .center,
            startAngle: .degrees(-45),
            endAngle: .degrees(315)
        )
    }
}

struct AnalyticsCardShell<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AnalyticsGlassEdgeArtwork(
                appearance: .resolve(reduceTransparency: reduceTransparency)
            )

            content
                .frame(
                    width: AnalyticsCardLayout.cardSize.width,
                    height: AnalyticsCardLayout.cardSize.height
                )
                .background {
                    ZStack {
                        if !reduceTransparency {
                            Rectangle()
                                .fill(.regularMaterial)
                        }

                        AnalyticsCardColors.cardBackground
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AnalyticsCardLayout.cardCornerRadius, style: .continuous))
        }
        .frame(
            width: AnalyticsCardLayout.rootSize.width,
            height: AnalyticsCardLayout.rootSize.height
        )
        .environment(\.colorScheme, .light)
    }
}
