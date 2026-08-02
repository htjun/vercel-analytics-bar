import SwiftUI
import VercelAnalyticsCore

@main
@MainActor
struct VercelAnalyticsBarApp: App {
    @State private var model: AppModel

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
            MenuBarRootView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                if let abbreviatedVisitors = model.abbreviatedVisitors {
                    Text(abbreviatedVisitors)
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
        }
    }
}
