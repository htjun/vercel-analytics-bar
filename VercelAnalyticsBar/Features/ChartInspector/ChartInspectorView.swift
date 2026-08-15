#if CHART_INSPECTOR
    import Foundation
    import Observation
    import SwiftUI
    import VercelAnalyticsCore

    struct ChartInspectorView: View {
        let model: AppModel
        let styleStore: ChartStyleStore
        @State private var pageState = ChartInspectorPageState()

        var body: some View {
            let preview = ChartInspectorPreview(analyticsState: model.state)

            HSplitView {
                ChartInspectorPreviewView(
                    preview: preview,
                    style: styleStore.style,
                    animationReplayToken: pageState.animationReplayToken
                )
                .frame(minWidth: 380, idealWidth: 380)

                inspectorPanel
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 740, minHeight: 560)
        }

        private var inspectorPanel: some View {
            ZStack {
                ChartInspectorWebView(
                    styleStore: styleStore,
                    pageState: pageState,
                    reloadToken: pageState.reloadToken
                )

                switch pageState.phase {
                case .loading:
                    ProgressView("Loading Chart Inspector…")
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                case .loaded:
                    EmptyView()
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Chart Inspector unavailable", systemImage: "exclamationmark.triangle")
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

    struct ChartInspectorPreviewView: View {
        let preview: ChartInspectorPreview
        let style: ChartStyle
        let animationReplayToken: Int

        var body: some View {
            VisitorsChart(
                points: preview.points,
                style: style,
                introPlayback: .inspector(replayToken: animationReplayToken)
            )
            .padding(16)
            .frame(width: 380, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    struct ChartInspectorPreview: Equatable {
        static let samplePoints = [
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 0), visitors: 18, pageViews: 32),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 1), visitors: 26, pageViews: 45),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 2), visitors: 12, pageViews: 22),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 3), visitors: 13, pageViews: 23),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 4), visitors: 28, pageViews: 48),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 5), visitors: 42, pageViews: 71),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 6), visitors: 14, pageViews: 25),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 7), visitors: 21, pageViews: 37),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 8), visitors: 286, pageViews: 492),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 9), visitors: 254, pageViews: 439),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 10), visitors: 157, pageViews: 274),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 11), visitors: 196, pageViews: 342),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 12), visitors: 28, pageViews: 49),
            VercelAnalyticsPoint(timestamp: sampleDate(dayOffset: 13), visitors: 7, pageViews: 13),
        ]

        let points: [VercelAnalyticsPoint]

        init(analyticsState: AppModel.State) {
            guard case let .loaded(snapshot) = analyticsState, !snapshot.series.isEmpty else {
                points = Self.samplePoints
                return
            }

            points = snapshot.series
        }

        private static func sampleDate(dayOffset: Int) -> Date {
            Date(timeIntervalSince1970: 1_784_419_200 + Double(dayOffset * 86400))
        }
    }

    @MainActor
    @Observable
    final class ChartInspectorPageState {
        enum Phase: Equatable {
            case loading
            case loaded
            case failed(String)
        }

        private(set) var phase: Phase = .loading
        private(set) var reloadToken = 0
        private(set) var animationReplayToken = 0

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

        func replayAnimation() {
            animationReplayToken += 1
        }
    }
#endif
