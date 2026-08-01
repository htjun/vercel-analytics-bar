import SwiftUI
import VercelAnalyticsCore

@main
struct VercelAnalyticsBarApp: App {
    @State private var model = AppModel(provider: FixtureAnalyticsSnapshotProvider())

    var body: some Scene {
        MenuBarExtra(ProductInfo.name, systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarRootView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
        }
    }
}
