import AppKit
import SwiftUI
import VercelAnalyticsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let chartStyle: ChartStyleStore
    private var statusBarController: StatusBarController?

    override init() {
        AppFontRegistry.registerBundledFonts()
        model = AppModel(
            projectProviderFactory: { token in
                VercelAPIClient(token: token)
            },
            analyticsProviderFactory: { token, project in
                VercelAnalyticsSnapshotProvider(token: token, project: project)
            }
        )
        chartStyle = ChartStyleStore()
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        model.startRefreshLoop()
        statusBarController = StatusBarController(model: model, chartStyle: chartStyle)
    }

    func applicationWillTerminate(_: Notification) {
        statusBarController?.tearDown()
        statusBarController = nil
        model.stopRefreshLoop()
    }
}

@main
@MainActor
struct VercelAnalyticsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(
                model: appDelegate.model,
                isChartInspectorEnabled: isChartInspectorEnabled
            )
        }

        #if CHART_INSPECTOR
            Window("Chart Inspector", id: ChartInspectorScene.id) {
                ChartInspectorView(
                    analyticsState: appDelegate.model.state,
                    styleStore: appDelegate.chartStyle
                )
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
