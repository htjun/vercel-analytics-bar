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

    private var isInstalled = true

    var isStatusItemVisible: Bool {
        statusItem.isVisible
    }

    init(
        model: AppModel,
        chartStyle: ChartStyleStore,
        statusBar: NSStatusBar = .system,
        companionWindows: @escaping () -> [NSWindow] = { [] }
    ) {
        self.model = model
        self.statusBar = statusBar
        let statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        let statusItemButton = statusItem.button
        panelController = AnalyticsPanelController(
            model: model,
            chartStyle: chartStyle,
            setStatusItemHighlighted: { statusItemButton?.highlight($0) },
            statusItemWindow: { statusItemButton?.window },
            companionWindows: companionWindows
        )
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
        let image = NSImage(named: "MenuBarChart")
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
            updateStatusItem(with: StatusItemPresentation(abbreviatedVisitors: model.abbreviatedVisitors))
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
        if panelController.isPresented {
            panelController.reposition(anchor: panelAnchor())
        }
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
