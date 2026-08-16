#if COMPONENT_EDITOR
    import Foundation
    import Observation
    import SwiftUI
    import VercelAnalyticsCore

    struct ComponentEditorView: View {
        let styleStore: ComponentStyleStore
        @State private var pageState = ComponentEditorPageState()
        @State private var selectedComponent: EditableComponent = .chart

        var body: some View {
            let preview = ComponentEditorPreview()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    componentTabs

                    switch selectedComponent {
                    case .chart:
                        ComponentEditorPreviewView(
                            preview: preview,
                            style: styleStore.chartStyle,
                            animationReplayToken: pageState.chartAnimationReplayToken
                        )
                    case .list:
                        ComponentEditorListPreviewView(
                            style: styleStore.listStyle,
                            animationReplayToken: pageState.listAnimationReplayToken
                        )
                    case .numbers:
                        ComponentEditorNumbersPreviewView(
                            style: styleStore.numberStyle,
                            value: pageState.numberPreviewValue
                        )
                    }
                }
                .frame(minWidth: 380, idealWidth: 480, maxHeight: .infinity, alignment: .topLeading)

                editorPanel
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 740, minHeight: 560)
        }

        private var componentTabs: some View {
            HStack(spacing: 16) {
                componentTab("Chart", component: .chart)
                componentTab("List", component: .list)
                componentTab("Numbers", component: .numbers)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }

        private func componentTab(_ title: String, component: EditableComponent) -> some View {
            let isSelected = selectedComponent == component
            return Button(title) {
                selectedComponent = component
            }
            .buttonStyle(.plain)
            .font(AppTypography.geistMedium12)
            .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.45))
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var editorPanel: some View {
            ZStack {
                ComponentEditorWebView(
                    styleStore: styleStore,
                    pageState: pageState,
                    selectedComponent: selectedComponent,
                    reloadToken: pageState.reloadToken
                )

                switch pageState.phase {
                case .loading:
                    ProgressView("Loading Component Editor…")
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                case .loaded:
                    EmptyView()
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Component Editor unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry") {
                            pageState.retry()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    struct ComponentEditorPreviewView: View {
        let preview: ComponentEditorPreview
        let style: ChartStyle
        let animationReplayToken: Int

        var body: some View {
            VisitorsChart(
                points: preview.points,
                style: style,
                introPlayback: .editor(replayToken: animationReplayToken)
            )
            .padding(16)
            .frame(width: 380, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    struct ComponentEditorListPreviewView: View {
        let style: BreakdownListStyle
        let animationReplayToken: Int
        @State private var selection = AnalyticsBreakdownSelection.pages
        @State private var hoveredSelection: AnalyticsBreakdownSelection?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var rows: [VercelAnalyticsBreakdown] {
            switch selection {
            case .pages:
                AnalyticsCardPresentation.pageFixtures
            case .referrals:
                AnalyticsCardPresentation.referralFixtures
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: style.headerToRowsSpacing) {
                HStack(spacing: style.tabSpacing) {
                    tab("Pages", selection: .pages)
                    tab("Referrals", selection: .referrals)
                }
                .frame(height: 16, alignment: .topLeading)

                StaggeredBreakdownRows(
                    rows: rows,
                    selection: selection,
                    style: style,
                    playback: .editor()
                ) { row in
                    HStack(spacing: style.columnSpacing) {
                        Text(row.label)
                            .font(font(weight: style.labelFontWeight, size: style.labelFontSize))
                            .tracking(style.labelTracking)
                            .foregroundStyle(Color(style.labelColor))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: labelWidth, alignment: .leading)

                        Text(AnalyticsCountFormatter.compact(row.visitors))
                            .font(font(weight: style.valueFontWeight, size: style.valueFontSize))
                            .tracking(style.valueTracking)
                            .foregroundStyle(Color(style.valueColor))
                            .lineLimit(1)
                            .frame(width: style.countColumnWidth, alignment: .trailing)
                    }
                    .frame(width: AnalyticsCardLayout.breakdownRowWidth, height: style.rowHeight)
                }
                .id(ListPreviewAnimationIdentity(
                    selection: selection,
                    replayToken: animationReplayToken
                ))
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }

        private var labelWidth: CGFloat {
            AnalyticsCardLayout.breakdownRowWidth - style.countColumnWidth - style.columnSpacing
        }

        private func tab(_ title: String, selection: AnalyticsBreakdownSelection) -> some View {
            let isSelected = self.selection == selection
            let opacity: Double = if isSelected {
                1
            } else if hoveredSelection == selection {
                style.hoveredTabOpacity
            } else {
                style.inactiveTabOpacity
            }

            return Button(title) {
                self.selection = selection
            }
            .buttonStyle(.plain)
            .font(font(weight: .medium, size: 12))
            .foregroundStyle(Color(style.tabTextColor).opacity(opacity))
            .animation(.easeInOut(duration: reduceMotion ? 0 : AnalyticsInteraction.hoverDuration), value: opacity)
            .onHover { isHovering in
                hoveredSelection = isHovering ? selection : nil
            }
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private func font(weight: ChartFontWeight, size: Double) -> Font {
            AppFontRegistry.font(
                postScriptName: "Geist-Regular",
                size: size,
                variations: [.weight: weight == .regular ? 400 : 450]
            )
        }

        private struct ListPreviewAnimationIdentity: Hashable {
            let selection: AnalyticsBreakdownSelection
            let replayToken: Int
        }
    }

    struct ComponentEditorNumbersPreviewView: View {
        let style: NumberStyle
        let value: Int

        var body: some View {
            ProportionalMetricText(value: value, style: style)
                .foregroundStyle(style.color.swiftUIColor)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    struct ComponentEditorPreview: Equatable {
        static let samplePoints: [VercelAnalyticsPoint] = {
            let values = [
                (15, 60), (23, 84), (34, 130), (24, 93), (28, 106), (20, 78),
                (18, 70), (40, 158), (84, 328), (73, 289), (29, 114), (14, 55),
                (19, 73), (39, 153), (57, 225), (62, 249), (52, 209), (49, 195),
                (33, 131), (23, 91), (20, 76), (17, 66), (17, 63), (12, 50),
            ]

            return values.enumerated().map { index, value in
                VercelAnalyticsPoint(
                    timestamp: sampleDate(hourOffset: index),
                    visitors: value.0,
                    pageViews: value.1
                )
            }
        }()

        let points: [VercelAnalyticsPoint]

        init() {
            self.init(points: Self.samplePoints)
        }

        init(analyticsState: AppModel.State) {
            guard case let .loaded(snapshot) = analyticsState, !snapshot.series.isEmpty else {
                self.init()
                return
            }

            self.init(points: snapshot.series)
        }

        private init(points: [VercelAnalyticsPoint]) {
            self.points = points
        }

        private static func sampleDate(hourOffset: Int) -> Date {
            Date(timeIntervalSince1970: 1_786_352_400 + Double(hourOffset * 3600))
        }
    }

    @MainActor
    @Observable
    final class ComponentEditorPageState {
        enum Phase: Equatable {
            case loading
            case loaded
            case failed(String)
        }

        private(set) var phase: Phase = .loading
        private(set) var reloadToken = 0
        private(set) var chartAnimationReplayToken = 0
        private(set) var listAnimationReplayToken = 0
        private(set) var numberPreviewValue = 325_922

        func startLoading() {
            phase = .loading
        }

        func finishLoading() {
            phase = .loaded
        }

        func fail(_ message: String) {
            phase = .failed(message)
        }

        func retry() {
            reloadToken += 1
            startLoading()
        }

        func replayAnimation(for component: EditableComponent) {
            switch component {
            case .chart:
                chartAnimationReplayToken += 1
            case .list:
                listAnimationReplayToken += 1
            case .numbers:
                break
            }
        }

        func setNumberPreviewValue(_ value: Int) {
            guard value >= 0 else { return }
            numberPreviewValue = value
        }
    }
#endif
