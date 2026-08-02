import SwiftUI
import VercelAnalyticsCore

@main
@MainActor
struct VercelAnalyticsBarApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel(
            provider: FixtureAnalyticsSnapshotProvider(),
            projectProviderFactory: { token in
                VercelAPIClient(token: token)
            }
        )
        _model = State(initialValue: model)

        Task {
            await model.restoreConnection()
        }
    }

    var body: some Scene {
        MenuBarExtra(ProductInfo.name, systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarRootView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
        }
    }
}
