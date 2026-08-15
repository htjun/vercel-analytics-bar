import AppKit
import Observation

struct StatusItemPresentation: Equatable {
    let title: String
    let accessibilityValue: String
    let toolTip: String

    init(abbreviatedVisitors: String?) {
        title = abbreviatedVisitors ?? ""
        if let abbreviatedVisitors {
            accessibilityValue = "\(abbreviatedVisitors) visitors in the last 24 hours"
            toolTip = "Vercel Analytics Bar — \(abbreviatedVisitors) visitors"
        } else {
            accessibilityValue = "Visitor data unavailable"
            toolTip = "Vercel Analytics Bar"
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let panelController: AnalyticsPanelController
    #if MOCK_MODE
        private let demoMetricTicker: DemoMetricTicker
    #endif

    private var isInstalled = true

    var isStatusItemVisible: Bool {
        statusItem.isVisible
    }

    init(
        model: AppModel,
        componentStyle: ComponentStyleStore,
        statusBar: NSStatusBar = .system,
        companionWindows: @escaping () -> [NSWindow] = { [] },
        onOpenSettings: @escaping (AdjacentWindowPresentationContext) -> Void = { _ in }
    ) {
        self.model = model
        self.statusBar = statusBar
        let statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        let statusItemButton = statusItem.button
        #if MOCK_MODE
            let demoMetricTicker = DemoMetricTicker()
            self.demoMetricTicker = demoMetricTicker
            panelController = AnalyticsPanelController(
                model: model,
                componentStyle: componentStyle,
                onOpenSettings: onOpenSettings,
                setStatusItemHighlighted: { statusItemButton?.highlight($0) },
                statusItemWindow: { statusItemButton?.window },
                companionWindows: companionWindows,
                demoMetricTicker: demoMetricTicker
            )
        #else
            panelController = AnalyticsPanelController(
                model: model,
                componentStyle: componentStyle,
                onOpenSettings: onOpenSettings,
                setStatusItemHighlighted: { statusItemButton?.highlight($0) },
                statusItemWindow: { statusItemButton?.window },
                companionWindows: companionWindows
            )
        #endif
        super.init()

        configureStatusItem()
        observeStatusItemPresentation()
    }

    func tearDown() {
        guard isInstalled else { return }
        isInstalled = false
        panelController.tearDown()
        statusBar.removeStatusItem(statusItem)
    }

    @objc
    private func togglePanel() {
        if panelController.isPresented {
            dismissPanel()
        } else {
            presentPanel()
        }
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "VercelAnalyticsBar.StatusItem"
        statusItem.behavior = [.removalAllowed, .terminationOnRemoval]
        statusItem.isVisible = true

        guard let button = statusItem.button else { return }
        let image = NSImage(named: "AnalyticsBarLogo")
        image?.isTemplate = true
        image?.size = CGSize(width: 16, height: 16)
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel("Vercel Analytics Bar")
    }

    private func observeStatusItemPresentation() {
        guard isInstalled else { return }
        withObservationTracking {
            #if MOCK_MODE
                let abbreviatedVisitors = model.abbreviatedVisitors(
                    applyingDemoOffsets: demoMetricTicker.offsets
                )
            #else
                let abbreviatedVisitors = model.abbreviatedVisitors
            #endif
            updateStatusItem(with: StatusItemPresentation(abbreviatedVisitors: abbreviatedVisitors))
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeStatusItemPresentation()
            }
        }
    }

    private func updateStatusItem(with presentation: StatusItemPresentation) {
        guard let button = statusItem.button else { return }
        button.title = presentation.title
        button.toolTip = presentation.toolTip
        button.setAccessibilityValue(presentation.accessibilityValue)
    }

    private func presentPanel() {
        panelController.present(anchor: panelAnchor())
    }

    private func dismissPanel() {
        panelController.dismiss()
    }

    private func panelAnchor() -> AnalyticsPanelAnchor? {
        guard let button = statusItem.button, let buttonWindow = button.window else { return nil }
        let anchorInWindow = button.convert(button.bounds, to: nil)
        let anchorOnScreen = buttonWindow.convertToScreen(anchorInWindow)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorOnScreen
        return AnalyticsPanelAnchor(frame: anchorOnScreen, visibleFrame: visibleFrame)
    }
}
