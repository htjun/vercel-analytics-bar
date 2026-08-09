import AppKit
import Observation
import SwiftUI

enum AnalyticsPanelPlacement {
    static let gap: CGFloat = 4
    static let screenMargin: CGFloat = 8

    static func frame(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = gap,
        margin: CGFloat = screenMargin
    ) -> CGRect {
        let availableMinX = visibleFrame.minX + margin
        let availableMaxX = visibleFrame.maxX - margin - panelSize.width
        let proposedX = anchor.midX - panelSize.width / 2
        let originX = min(max(proposedX, availableMinX), max(availableMinX, availableMaxX))

        let availableMinY = visibleFrame.minY + margin
        let proposedY = anchor.minY - gap - panelSize.height
        let originY = max(proposedY, availableMinY)

        return CGRect(origin: CGPoint(x: originX, y: originY), size: panelSize)
    }
}

struct StatusItemPresentation: Equatable {
    let title: String
    let accessibilityValue: String
    let toolTip: String

    init(abbreviatedVisitors: String?) {
        title = abbreviatedVisitors ?? ""
        if let abbreviatedVisitors {
            accessibilityValue = "\(abbreviatedVisitors) visitors in the last 24 hours"
            toolTip = "Vercel Analytics — \(abbreviatedVisitors) visitors"
        } else {
            accessibilityValue = "Visitor data unavailable"
            toolTip = "Vercel Analytics"
        }
    }
}

struct AnalyticsPanelPresentationState {
    private(set) var isPresented = false
    private(set) var sessionID = UUID()

    mutating func present() {
        sessionID = UUID()
        isPresented = true
    }

    mutating func dismiss() {
        isPresented = false
    }
}

@MainActor
enum AnalyticsPanelEventPolicy {
    static func keepsPanelOpen(
        for eventWindow: NSWindow?,
        panel: NSWindow,
        statusItemWindow: NSWindow?
    ) -> Bool {
        guard let eventWindow else { return false }
        if eventWindow === panel || eventWindow === statusItemWindow {
            return true
        }

        var ancestor = eventWindow.parent
        while let window = ancestor {
            if window === panel { return true }
            ancestor = window.parent
        }
        return false
    }
}

@MainActor
final class AnalyticsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(hostingView: NSView) {
        super.init(
            contentRect: CGRect(origin: .zero, size: AnalyticsCardLayout.rootSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
        isFloatingPanel = true
        level = .popUpMenu
        becomesKeyOnlyIfNeeded = true
        contentView = Self.makeMaterialView(hosting: hostingView)
    }

    private static func makeMaterialView(hosting hostingView: NSView) -> NSView {
        #if compiler(>=6.2)
            if #available(macOS 26, *) {
                let glassView = NSGlassEffectView()
                glassView.style = .clear
                glassView.tintColor = nil
                glassView.cornerRadius = AnalyticsCardLayout.outerCornerRadius
                glassView.contentView = hostingView
                return glassView
            }
        #endif

        let materialView = NSVisualEffectView()
        materialView.material = .underWindowBackground
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = AnalyticsCardLayout.outerCornerRadius
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: materialView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),
        ])
        return materialView
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let chartStyle: ChartStyleStore
    private let onOpenSettings: () -> Void
    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let hostingView: NSHostingView<AnyView>
    private let panel: AnalyticsPanel

    private var presentationState = AnalyticsPanelPresentationState()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var presentationTask: Task<Void, Never>?
    private var isInstalled = true

    var isStatusItemVisible: Bool {
        statusItem.isVisible
    }

    init(
        model: AppModel,
        chartStyle: ChartStyleStore,
        statusBar: NSStatusBar = .system,
        onOpenSettings: @escaping () -> Void
    ) {
        self.model = model
        self.chartStyle = chartStyle
        self.onOpenSettings = onOpenSettings
        self.statusBar = statusBar
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        panel = AnalyticsPanel(hostingView: hostingView)
        super.init()

        configureStatusItem()
        updateHostedContent()
        observeStatusItemPresentation()
    }

    func tearDown() {
        guard isInstalled else { return }
        isInstalled = false
        presentationTask?.cancel()
        presentationTask = nil
        dismissPanel()
        statusBar.removeStatusItem(statusItem)
    }

    @objc
    private func togglePanel() {
        if presentationState.isPresented {
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
        button.setAccessibilityLabel("Vercel Analytics")
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
        if presentationState.isPresented {
            positionPanel()
        }
    }

    private func presentPanel() {
        presentationState.present()
        updateHostedContent()
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)
        installEventMonitors()

        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            guard let self else { return }
            await model.restoreConnection()
            guard !Task.isCancelled else { return }
            await model.load()
        }
    }

    private func dismissPanel() {
        guard presentationState.isPresented || panel.isVisible else { return }
        presentationState.dismiss()
        panel.childWindows?.forEach { $0.orderOut(nil) }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        removeEventMonitors()
    }

    private func updateHostedContent() {
        let sessionID = presentationState.sessionID
        hostingView.rootView = AnyView(
            MenuBarRootView(
                model: model,
                chartStyle: chartStyle,
                onOpenSettings: onOpenSettings,
                onDismissPanel: { [weak self] in
                    self?.dismissPanel()
                }
            )
            .id(sessionID)
        )
    }

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchorInWindow = button.convert(button.bounds, to: nil)
        let anchorOnScreen = buttonWindow.convertToScreen(anchorInWindow)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorOnScreen
        panel.setFrame(
            AnalyticsPanelPlacement.frame(
                anchor: anchorOnScreen,
                panelSize: AnalyticsCardLayout.rootSize,
                visibleFrame: visibleFrame
            ),
            display: true
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, presentationState.isPresented else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                if panel.childWindows?.isEmpty != false {
                    dismissPanel()
                    return nil
                }
                return event
            }
            guard !AnalyticsPanelEventPolicy.keepsPanelOpen(
                for: event.window,
                panel: panel,
                statusItemWindow: statusItem.button?.window
            ) else {
                return event
            }
            dismissPanel()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPanel()
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}
