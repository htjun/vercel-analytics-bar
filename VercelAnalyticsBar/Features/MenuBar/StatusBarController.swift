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

    static func shadowFrame(forGlassFrame glassFrame: CGRect) -> CGRect {
        glassFrame.insetBy(
            dx: -AnalyticsCardLayout.panelShadowPadding,
            dy: -AnalyticsCardLayout.panelShadowPadding
        )
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
        statusItemWindow: NSWindow?,
        companionWindows: [NSWindow] = []
    ) -> Bool {
        guard let eventWindow else { return false }
        if eventWindow === panel
            || eventWindow === statusItemWindow
            || companionWindows.contains(where: { $0 === eventWindow })
        {
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
final class AnalyticsPanelShadowView: NSView {
    let shadowLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let padding = AnalyticsCardLayout.panelShadowPadding
        let glassFrame = bounds.insetBy(dx: padding, dy: padding)
        shadowLayer.frame = glassFrame
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = AnalyticsCardLayout.panelShadowOpacity
        shadowLayer.shadowRadius = AnalyticsCardLayout.panelShadowRadius
        shadowLayer.shadowOffset = AnalyticsCardLayout.panelShadowOffset
        shadowLayer.shadowPath = CGPath(
            roundedRect: shadowLayer.bounds,
            cornerWidth: AnalyticsCardLayout.outerCornerRadius,
            cornerHeight: AnalyticsCardLayout.outerCornerRadius,
            transform: nil
        )
        layer?.addSublayer(shadowLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class AnalyticsPanelShadowWindow: NSPanel {
    let shadowView: AnalyticsPanelShadowView

    init() {
        shadowView = AnalyticsPanelShadowView(
            frame: CGRect(origin: .zero, size: AnalyticsCardLayout.panelShadowWindowSize)
        )
        super.init(
            contentRect: CGRect(origin: .zero, size: AnalyticsCardLayout.panelShadowWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isFloatingPanel = true
        level = .popUpMenu
        contentView = shadowView
    }
}

@MainActor
final class AnalyticsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    let materialView: NSView
    let shadowWindow: AnalyticsPanelShadowWindow

    init(hostingView: NSView) {
        materialView = Self.makeMaterialView(hosting: hostingView)
        shadowWindow = AnalyticsPanelShadowWindow()
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
        contentView = materialView
        addChildWindow(shadowWindow, ordered: .below)
    }

    var hasTransientChildWindows: Bool {
        childWindows?.contains { $0 !== shadowWindow && $0.isVisible } == true
    }

    func orderOutTransientChildWindows() {
        childWindows?
            .filter { $0 !== shadowWindow }
            .forEach { $0.orderOut(nil) }
    }

    func setGlassFrame(_ glassFrame: CGRect, display: Bool) {
        setFrame(glassFrame, display: display)
        shadowWindow.setFrame(
            AnalyticsPanelPlacement.shadowFrame(forGlassFrame: glassFrame),
            display: display
        )
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
    private let companionWindows: () -> [NSWindow]
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
        companionWindows: @escaping () -> [NSWindow] = { [] },
        onOpenSettings: @escaping () -> Void
    ) {
        self.model = model
        self.chartStyle = chartStyle
        self.companionWindows = companionWindows
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
        panel.orderOutTransientChildWindows()
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
        let glassFrame = AnalyticsPanelPlacement.frame(
            anchor: anchorOnScreen,
            panelSize: AnalyticsCardLayout.rootSize,
            visibleFrame: visibleFrame
        )
        panel.setGlassFrame(glassFrame, display: true)
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, presentationState.isPresented else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                if !panel.hasTransientChildWindows {
                    dismissPanel()
                    return nil
                }
                return event
            }
            guard !AnalyticsPanelEventPolicy.keepsPanelOpen(
                for: event.window,
                panel: panel,
                statusItemWindow: statusItem.button?.window,
                companionWindows: companionWindows()
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
