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
            #if MOCK_MODE
                let preview = ChartInspectorPreview(analyticsState: model.state)
            #else
            let preview = ChartInspectorPreview()
            #endif

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
