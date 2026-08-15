// swiftlint:disable file_length
import SwiftUI
import VercelAnalyticsCore

struct AnalyticsCardMetric: Equatable {
    enum Trend: Equatable {
        case positive
        case negative
        case neutral
    }

    let label: String
    let value: Int
    let comparisonText: String
    let trend: Trend

    init(metric: AnalyticsMetric) {
        label = metric.label
        value = metric.value

        switch metric.comparison {
        case let .percentage(change):
            let roundedChange = Int(change.rounded())
            comparisonText = roundedChange > 0 ? "+\(roundedChange)%" : "\(roundedChange)%"
            if roundedChange > 0 {
                trend = .positive
            } else if roundedChange < 0 {
                trend = .negative
            } else {
                trend = .neutral
            }
        case .new:
            comparisonText = "New"
            trend = .positive
        }
    }

    init(label: String, value: Int, comparisonText: String, trend: Trend) {
        self.label = label
        self.value = value
        self.comparisonText = comparisonText
        self.trend = trend
    }

    var valueText: String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }
}

enum AnalyticsBreakdownSelection: Equatable {
    case pages
    case referrals
}

struct AnalyticsCardPresentation: Equatable {
    let projectName: String
    let selectedRange: VercelAnalyticsRange
    let visitors: AnalyticsCardMetric
    let pageViews: AnalyticsCardMetric
    let series: [VercelAnalyticsPoint]
    let topPages: [VercelAnalyticsBreakdown]
    let topReferrers: [VercelAnalyticsBreakdown]
    let updatedText: String
    let dashboardURL: URL?

    static let pageFixtures = [
        VercelAnalyticsBreakdown(
            label: "/docs/getting-started",
            visitors: 710,
            pageViews: 872
        ),
        VercelAnalyticsBreakdown(label: "/products/analytics", visitors: 175, pageViews: 202),
        VercelAnalyticsBreakdown(
            label: "/blog/example-release",
            visitors: 52,
            pageViews: 60
        ),
        VercelAnalyticsBreakdown(label: "/pricing", visitors: 24, pageViews: 29),
        VercelAnalyticsBreakdown(
            label: "/about",
            visitors: 25,
            pageViews: 28
        ),
    ]

    static let referralFixtures = [
        VercelAnalyticsBreakdown(label: "google.com", visitors: 510, pageViews: 640),
        VercelAnalyticsBreakdown(label: "news.ycombinator.com", visitors: 205, pageViews: 260),
        VercelAnalyticsBreakdown(label: "github.com", visitors: 160, pageViews: 195),
    ]

    static let sampleFixture = AnalyticsCardPresentation(
        projectName: "example-site",
        selectedRange: .last30Days,
        visitors: AnalyticsCardMetric(label: "Visitors", value: 3234, comparisonText: "+177%", trend: .positive),
        pageViews: AnalyticsCardMetric(label: "Page Views", value: 6423, comparisonText: "-2%", trend: .negative),
        series: fixtureSeries,
        topPages: pageFixtures,
        topReferrers: referralFixtures,
        updatedText: "Opened 6:38 pm",
        dashboardURL: URL(string: "https://vercel.com")
    )

    private static let fixtureSeries: [VercelAnalyticsPoint] = {
        let start = Date(timeIntervalSince1970: 1_785_628_800)
        let visitors = [12, 18, 14, 25, 19, 31, 28, 42, 36, 48, 40, 56]
        return visitors.enumerated().map { index, value in
            VercelAnalyticsPoint(
                timestamp: start.addingTimeInterval(Double(index) * 86400),
                visitors: value,
                pageViews: value * 2
            )
        }
    }()

    func breakdownRows(for selection: AnalyticsBreakdownSelection) -> [VercelAnalyticsBreakdown] {
        switch selection {
        case .pages:
            topPages
        case .referrals:
            topReferrers
        }
    }

    func emptyBreakdownText(for selection: AnalyticsBreakdownSelection) -> String {
        switch selection {
        case .pages:
            "No page data"
        case .referrals:
            "No referral data"
        }
    }
}

struct AnalyticsCardView<SelectorContent: View>: View {
    let presentation: AnalyticsCardPresentation
    let chartStyle: ChartStyle
    var chartIntroPlayback: ChartIntroPlayback?
    @Binding var isProjectSelectorPresented: Bool
    @Binding var selectedBreakdown: AnalyticsBreakdownSelection
    @ViewBuilder let projectSelectorContent: () -> SelectorContent
    let onSelectProject: () -> Void
    let onSelectRange: (VercelAnalyticsRange) -> Void
    let onOpenSettings: () -> Void
    let onOpenDashboard: (URL) -> Void
    @State private var isRangeSelectorPresented = false

    var body: some View {
        AnalyticsCardShell {
            ZStack(alignment: .topLeading) {
                header
                    .offset(x: 8, y: 8)

                metric(presentation.visitors)
                    .offset(x: 20, y: 62)

                metric(presentation.pageViews)
                    .offset(x: 208, y: 62)

                VisitorsChart(
                    points: presentation.series,
                    style: chartStyle,
                    introPlayback: chartIntroPlayback
                )
                .frame(width: 368)
                .offset(x: AnalyticsCardLayout.chartFrame.minX, y: AnalyticsCardLayout.chartFrame.minY)

                breakdown
                    .offset(x: 20, y: 340)

                updatedLabel
                    .offset(x: 20, y: 515)

                dashboardLink
                    .offset(x: 254, y: 508)
            }
            .frame(width: 384, height: 546, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            selectorGroup
            Spacer(minLength: 0)
            Button(action: onOpenSettings) {
                Image("SettingsSliders")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .analyticsHoverBackground(in: Circle())
            .overlay(Circle().stroke(AnalyticsCardColors.border, lineWidth: 1))
            .accessibilityLabel("Open Settings")
        }
        .frame(width: 368, height: 30)
    }

    private var selectorGroup: some View {
        HStack(spacing: 0) {
            Button(action: onSelectProject) {
                selectorLabel(title: presentation.projectName, width: 150)
            }
            .buttonStyle(.plain)
            .analyticsHoverBackground(in: Rectangle())
            .accessibilityLabel("Project: \(presentation.projectName)")
            .popover(isPresented: $isProjectSelectorPresented, arrowEdge: .top) {
                projectSelectorContent()
            }

            Button {
                isRangeSelectorPresented.toggle()
            } label: {
                selectorLabel(title: presentation.selectedRange.title, width: 115)
            }
            .buttonStyle(.plain)
            .analyticsHoverBackground(in: Rectangle())
            .accessibilityLabel("Range: \(presentation.selectedRange.title)")
            .popover(isPresented: $isRangeSelectorPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(VercelAnalyticsRange.allCases, id: \.self) { range in
                        Button(range.title) {
                            isRangeSelectorPresented = false
                            onSelectRange(range)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 265, height: 30)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AnalyticsCardColors.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AnalyticsCardColors.border)
                .frame(width: 1, height: 30)
                .offset(x: 149.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func selectorLabel(title: String, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .font(AppTypography.geistSelector12)
                .foregroundStyle(AnalyticsCardColors.primaryText)
                .lineLimit(1)
                .allowsTightening(true)
                .truncationMode(.tail)
                .frame(width: width - 36, height: 16, alignment: .leading)
                .offset(x: 12, y: 7)

            Image("DropdownChevron")
                .resizable()
                .frame(width: 12, height: 12)
                .offset(x: width - 21, y: 9)
        }
        .frame(width: width, height: 30, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func metric(_ metric: AnalyticsCardMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(metric.label)
                    .font(AppTypography.geistMetricLabel12)
                    .foregroundStyle(AnalyticsCardColors.secondaryText)

                Text(metric.comparisonText)
                    .font(AppTypography.interComparison12)
                    .foregroundStyle(comparisonColor(for: metric.trend))
            }
            .frame(height: 16, alignment: .topLeading)

            ProportionalMetricText(value: metric.value)
                .foregroundStyle(AnalyticsCardColors.primaryText)
        }
        .frame(width: 114, height: 80, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var breakdown: some View {
        let rows = presentation.breakdownRows(for: selectedBreakdown)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                breakdownTab("Pages", selection: .pages)
                breakdownTab("Referrals", selection: .referrals)
            }
            .frame(height: 16, alignment: .topLeading)

            if rows.isEmpty {
                Text(presentation.emptyBreakdownText(for: selectedBreakdown))
                    .font(AppTypography.geistRegular12)
                    .foregroundStyle(AnalyticsCardColors.secondaryText)
                    .frame(width: AnalyticsCardLayout.breakdownRowWidth, height: 16, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.prefix(5)) { row in
                        HStack(spacing: AnalyticsCardLayout.breakdownColumnSpacing) {
                            Text(row.label)
                                .font(AppTypography.geistRegular12)
                                .tracking(AppTypography.breakdownTracking)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: AnalyticsCardLayout.breakdownLabelWidth, alignment: .leading)

                            Text(AnalyticsCountFormatter.compact(row.visitors))
                                .font(AppTypography.geistMedium12)
                                .tracking(AppTypography.breakdownTracking)
                                .lineLimit(1)
                                .frame(width: AnalyticsCardLayout.breakdownCountWidth, alignment: .trailing)
                                .accessibilityLabel(
                                    row.visitors.formatted(
                                        .number.grouping(.automatic).locale(Locale(identifier: "en_US"))
                                    )
                                )
                        }
                        .foregroundStyle(AnalyticsCardColors.primaryText)
                        .frame(width: AnalyticsCardLayout.breakdownRowWidth, height: 16)
                    }
                }
            }
        }
        .frame(width: AnalyticsCardLayout.breakdownRowWidth, height: 144, alignment: .topLeading)
    }

    private func breakdownTab(
        _ title: String,
        selection: AnalyticsBreakdownSelection
    ) -> some View {
        let isSelected = selectedBreakdown == selection
        return Button(title) {
            selectedBreakdown = selection
        }
        .buttonStyle(.plain)
        .font(AppTypography.geistMedium12)
        .foregroundStyle(AnalyticsCardColors.primaryText.opacity(isSelected ? 1 : 0.4))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var updatedLabel: some View {
        Text(presentation.updatedText)
            .font(AppTypography.geistMedium12)
            .foregroundStyle(AnalyticsCardColors.secondaryText)
            .lineLimit(1)
            .frame(width: 180, height: 16, alignment: .leading)
    }

    @ViewBuilder
    private var dashboardLink: some View {
        if let dashboardURL = presentation.dashboardURL {
            Button {
                onOpenDashboard(dashboardURL)
            } label: {
                dashboardLabel
            }
            .buttonStyle(.plain)
            .help("Open this project's analytics in Vercel")
        } else {
            dashboardLabel
        }
    }

    private var dashboardLabel: some View {
        HStack(spacing: 8) {
            Text("View in Vercel")
                .font(AppTypography.geistMedium12)
                .foregroundStyle(AnalyticsCardColors.primaryText)

            Image("ExternalArrow")
                .resizable()
                .frame(width: 12, height: 12)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(width: 122, height: 30)
        .analyticsHoverBackground(in: Capsule())
        .overlay(Capsule().stroke(AnalyticsCardColors.border, lineWidth: 1))
        .contentShape(Capsule())
    }

    private func comparisonColor(for trend: AnalyticsCardMetric.Trend) -> Color {
        switch trend {
        case .positive:
            AnalyticsCardColors.positive
        case .negative:
            AnalyticsCardColors.negative
        case .neutral:
            AnalyticsCardColors.secondaryText
        }
    }
}

enum AnalyticsInteraction {
    static let hoverDuration = 0.2
    static let hoverBackgroundOpacity = 0.9
}

private struct AnalyticsHoverBackground<HoverShape: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    let shape: HoverShape

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(
                    Color.white.opacity(isHovering ? AnalyticsInteraction.hoverBackgroundOpacity : 0)
                )
            )
            .animation(
                .easeInOut(duration: reduceMotion ? 0 : AnalyticsInteraction.hoverDuration),
                value: isHovering
            )
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func analyticsHoverBackground(in shape: some Shape) -> some View {
        modifier(AnalyticsHoverBackground(shape: shape))
    }
}
