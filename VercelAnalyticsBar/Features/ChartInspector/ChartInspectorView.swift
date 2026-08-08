#if CHART_INSPECTOR
    import Observation
    import SwiftUI

    enum ChartInspectorScene {
        static let id = "chart-inspector"
    }

    struct ChartInspectorView: View {
        let styleStore: ChartStyleStore
        @State private var pageState = ChartInspectorPageState()

        var body: some View {
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
            .frame(minWidth: 320, minHeight: 560)
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
    }
#endif
