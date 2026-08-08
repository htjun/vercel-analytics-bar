import SwiftUI
import VercelAnalyticsCore

@main
@MainActor
struct VercelAnalyticsBarApp: App {
    @State private var model: AppModel
    @State private var chartStyle = ChartStyleStore()

    init() {
        let model = AppModel(
            projectProviderFactory: { token in
                VercelAPIClient(token: token)
            },
            analyticsProviderFactory: { token, project in
                VercelAnalyticsSnapshotProvider(token: token, project: project)
            }
        )
        model.startRefreshLoop()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(
                model: model,
                chartStyle: chartStyle,
                isChartInspectorEnabled: isChartInspectorEnabled
            )
        } label: {
            HStack(spacing: 4) {
                Image("MenuBarChart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Visitors")
                if let abbreviatedVisitors = model.abbreviatedVisitors {
                    Text(abbreviatedVisitors)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
        }

        #if CHART_INSPECTOR
            Window("Chart Inspector", id: ChartInspectorScene.id) {
                ChartInspectorView(analyticsState: model.state, styleStore: chartStyle)
            }
            .defaultSize(width: 820, height: 640)
            .windowResizability(.contentMinSize)
        #endif
    }

    private var isChartInspectorEnabled: Bool {
        #if CHART_INSPECTOR
            ChartInspectorSource.isInspectorEnabled()
        #else
            false
        #endif
    }
}
