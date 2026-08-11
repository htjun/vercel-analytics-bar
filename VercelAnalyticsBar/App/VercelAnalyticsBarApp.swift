import AppKit
import VercelAnalyticsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let chartStyle: ChartStyleStore
    private var statusBarController: StatusBarController?
    private var settingsWindowController: HostedWindowController?
    #if CHART_INSPECTOR
        private var chartInspectorWindowController: HostedWindowController?
    #endif

    override init() {
        AppFontRegistry.registerBundledFonts()
        #if MOCK_MODE
            model = DemoAppModelFactory.makeModel()
        #else
            model = AppModel(
                projectProviderFactory: { token in
                    VercelAPIClient(token: token)
                },
                analyticsProviderFactory: { token, project in
                    VercelAnalyticsSnapshotProvider(token: token, project: project)
                }
            )
        #endif
        chartStyle = ChartStyleStore()
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        model.startRefreshLoop()
        settingsWindowController = makeSettingsWindowController()
        statusBarController = StatusBarController(
            model: model,
            chartStyle: chartStyle,
            companionWindows: { [weak self] in
                [self?.settingsWindowController?.window].compactMap(\.self)
            },
            onOpenSettings: { [weak self] in
                self?.settingsWindowController?.present()
            }
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_: Notification) {
        statusBarController?.tearDown()
        statusBarController = nil
        settingsWindowController = nil
        #if CHART_INSPECTOR
            chartInspectorWindowController = nil
        #endif
        model.stopRefreshLoop()
    }

    private func makeSettingsWindowController() -> HostedWindowController {
        HostedWindowController(
            title: "\(ProductInfo.name) Settings",
            contentSize: CGSize(width: 520, height: 680),
            rootView: SettingsRootView(
                model: model,
                isChartInspectorEnabled: isChartInspectorEnabled,
                onOpenChartInspector: { [weak self] in
                    self?.presentChartInspector()
                }
            )
        )
    }

    private func presentChartInspector() {
        #if CHART_INSPECTOR
            guard isChartInspectorEnabled else { return }
            if chartInspectorWindowController == nil {
                chartInspectorWindowController = HostedWindowController(
                    title: "Chart Inspector",
                    contentSize: CGSize(width: 820, height: 640),
                    minimumContentSize: CGSize(width: 740, height: 560),
                    isResizable: true,
                    rootView: ChartInspectorView(
                        model: model,
                        styleStore: chartStyle
                    )
                )
            }
            chartInspectorWindowController?.present()
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

@MainActor
enum ApplicationMenu {
    static func make(for application: NSApplication) -> NSMenu {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: ProductInfo.name)
        let quitItem = NSMenuItem(
            title: "Quit \(ProductInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = application
        applicationMenu.addItem(quitItem)
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        return mainMenu
    }
}

@main
@MainActor
enum VercelAnalyticsBarApplication {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.mainMenu = ApplicationMenu.make(for: application)

        withExtendedLifetime(appDelegate) {
            application.run()
        }
    }
}
