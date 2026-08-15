import AppKit
import SwiftUI

struct AnalyticsPanelAnchor: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum AnalyticsPanelEventInput {
    case escape
    case pointerDown(window: NSWindow?)
    case globalPointerDown
}

enum AnalyticsPanelEventResult: Equatable {
    case passThrough
    case consume
}

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

@MainActor
final class AnalyticsPanelController {
    let window: AnalyticsPanel
    private(set) var isPresented = false
    private(set) var sessionID = UUID()

    var hasLocalEventMonitor: Bool {
        localEventMonitor != nil
    }

    var hasGlobalEventMonitor: Bool {
        globalEventMonitor != nil
    }

    private let model: AppModel
    private let componentStyle: ComponentStyleStore
    private let onOpenSettings: (AdjacentWindowPresentationContext) -> Void
    private let setStatusItemHighlighted: (Bool) -> Void
    private let statusItemWindow: () -> NSWindow?
    private let companionWindows: () -> [NSWindow]
    private let hostingView: NSHostingView<AnyView>
    private let chartIntroPlaybackGate = ChartIntroPlaybackGate()
    private let breakdownListIntroPlaybackGate = BreakdownListIntroPlaybackGate()
    #if MOCK_MODE
        private let demoMetricTicker: DemoMetricTicker
    #endif
    #if MOCK_MODE
        private var openedAt = Date()
    #endif
    private var presentationTask: Task<Void, Never>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(
        model: AppModel,
        componentStyle: ComponentStyleStore,
        onOpenSettings: @escaping (AdjacentWindowPresentationContext) -> Void = { _ in },
        setStatusItemHighlighted: @escaping (Bool) -> Void,
        statusItemWindow: @escaping () -> NSWindow? = { nil },
        companionWindows: @escaping () -> [NSWindow] = { [] },
        demoMetricTicker: Any? = nil
    ) {
        self.model = model
        self.componentStyle = componentStyle
        self.onOpenSettings = onOpenSettings
        self.setStatusItemHighlighted = setStatusItemHighlighted
        self.statusItemWindow = statusItemWindow
        self.companionWindows = companionWindows
        #if MOCK_MODE
            self.demoMetricTicker = (demoMetricTicker as? DemoMetricTicker) ?? DemoMetricTicker()
        #endif
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window = AnalyticsPanel(hostingView: hostingView)
        updateHostedContent()
    }

    func present(anchor: AnalyticsPanelAnchor?) {
        guard !isPresented else { return }

        sessionID = UUID()
        isPresented = true
        #if MOCK_MODE
            openedAt = Date()
            demoMetricTicker.start()
        #endif
        updateHostedContent()
        applyInitialPlacement(anchor: anchor)
        window.orderFrontRegardless()
        window.makeKey()
        setStatusItemHighlighted(true)
        installEventMonitors()

        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            guard let self else { return }
            await model.restoreConnection()
            guard !Task.isCancelled else { return }
            #if MOCK_MODE
                await model.loadDemoSnapshotIfNeeded()
            #else
                await model.load()
            #endif
        }
    }

    func dismiss() {
        removeEventMonitors()
        #if MOCK_MODE
            demoMetricTicker.stop()
        #endif
        guard isPresented || window.isVisible else { return }
        isPresented = false
        window.orderOutTransientChildWindows()
        window.orderOut(nil)
        setStatusItemHighlighted(false)
    }

    private func applyInitialPlacement(anchor: AnalyticsPanelAnchor?) {
        guard isPresented, let anchor else { return }
        let glassFrame = AnalyticsPanelPlacement.frame(
            anchor: anchor.frame,
            panelSize: AnalyticsCardLayout.rootSize,
            visibleFrame: anchor.visibleFrame
        )
        window.setGlassFrame(glassFrame, display: true)
    }

    func tearDown() {
        presentationTask?.cancel()
        presentationTask = nil
        #if MOCK_MODE
            demoMetricTicker.stop()
        #endif
        dismiss()
        removeEventMonitors()
    }

    func handle(_ input: AnalyticsPanelEventInput) -> AnalyticsPanelEventResult {
        guard isPresented else { return .passThrough }

        switch input {
        case .escape:
            guard !window.hasTransientChildWindows else { return .passThrough }
            dismiss()
            return .consume
        case let .pointerDown(eventWindow):
            guard !keepsPanelOpen(for: eventWindow) else { return .passThrough }
            dismiss()
            return .passThrough
        case .globalPointerDown:
            dismiss()
            return .passThrough
        }
    }

    // swiftlint:disable:next function_body_length
    private func updateHostedContent() {
        let sessionID = sessionID
        let chartIntroPlayback: ChartIntroPlayback? = if isPresented {
            #if MOCK_MODE
                ChartIntroPlayback.panel(
                    sessionID: sessionID,
                    scope: .session(sessionID),
                    gate: chartIntroPlaybackGate
                )
            #else
                ChartIntroPlayback.panel(
                    sessionID: sessionID,
                    scope: .application,
                    gate: chartIntroPlaybackGate
                )
            #endif
        } else {
            nil
        }
        let breakdownListIntroPlayback: BreakdownListIntroPlayback? = if isPresented {
            #if MOCK_MODE
                BreakdownListIntroPlayback.panel(
                    scope: .session(sessionID),
                    gate: breakdownListIntroPlaybackGate
                )
            #else
                BreakdownListIntroPlayback.panel(
                    scope: .application,
                    gate: breakdownListIntroPlaybackGate
                )
            #endif
        } else {
            nil
        }
        #if MOCK_MODE
            let rootView = MenuBarRootView(
                model: model,
                componentStyle: componentStyle,
                chartIntroPlayback: chartIntroPlayback,
                breakdownListIntroPlayback: breakdownListIntroPlayback,
                demoMetricTicker: demoMetricTicker,
                openedAt: openedAt,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onDismissPanel: { [weak self] in
                    self?.dismiss()
                }
            )
        #else
            let rootView = MenuBarRootView(
                model: model,
                componentStyle: componentStyle,
                chartIntroPlayback: chartIntroPlayback,
                breakdownListIntroPlayback: breakdownListIntroPlayback,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onDismissPanel: { [weak self] in
                    self?.dismiss()
                }
            )
        #endif
        hostingView.rootView = AnyView(
            rootView.id(sessionID)
        )
    }

    private func openSettings() {
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame
        onOpenSettings(AdjacentWindowPresentationContext(
            anchorFrame: window.frame,
            visibleFrame: visibleFrame
        ))
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            let input: AnalyticsPanelEventInput = if event.type == .keyDown, event.keyCode == 53 {
                .escape
            } else {
                .pointerDown(window: event.window)
            }
            return handle(input) == .consume ? nil : event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.handle(.globalPointerDown)
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

    private func keepsPanelOpen(for eventWindow: NSWindow?) -> Bool {
        guard let eventWindow else { return false }
        let isOwnedWindow = eventWindow === window
            || eventWindow === statusItemWindow()
            || companionWindows().contains(where: { $0 === eventWindow })
        if isOwnedWindow {
            return true
        }

        var ancestor = eventWindow.parent
        while let ancestorWindow = ancestor {
            if ancestorWindow === window { return true }
            ancestor = ancestorWindow.parent
        }
        return false
    }
}
