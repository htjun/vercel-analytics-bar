import AppKit
import SwiftUI

struct AnalyticsPanelAnchor: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
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
    var onPresentationChanged: ((Bool) -> Void)?

    private let model: AppModel
    private let chartStyle: ChartStyleStore
    private let onOpenSettings: () -> Void
    private let setStatusItemHighlighted: (Bool) -> Void
    private let hostingView: NSHostingView<AnyView>
    private var presentationTask: Task<Void, Never>?

    init(
        model: AppModel,
        chartStyle: ChartStyleStore,
        onOpenSettings: @escaping () -> Void,
        setStatusItemHighlighted: @escaping (Bool) -> Void
    ) {
        self.model = model
        self.chartStyle = chartStyle
        self.onOpenSettings = onOpenSettings
        self.setStatusItemHighlighted = setStatusItemHighlighted
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window = AnalyticsPanel(hostingView: hostingView)
        updateHostedContent()
    }

    func present(anchor: AnalyticsPanelAnchor?) {
        guard !isPresented else {
            reposition(anchor: anchor)
            return
        }

        sessionID = UUID()
        isPresented = true
        updateHostedContent()
        reposition(anchor: anchor)
        window.orderFrontRegardless()
        window.makeKey()
        setStatusItemHighlighted(true)
        onPresentationChanged?(true)

        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            guard let self else { return }
            await model.restoreConnection()
            guard !Task.isCancelled else { return }
            await model.load()
        }
    }

    func dismiss() {
        guard isPresented || window.isVisible else { return }
        isPresented = false
        window.orderOutTransientChildWindows()
        window.orderOut(nil)
        setStatusItemHighlighted(false)
        onPresentationChanged?(false)
    }

    func reposition(anchor: AnalyticsPanelAnchor?) {
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
        dismiss()
    }

    private func updateHostedContent() {
        let sessionID = sessionID
        hostingView.rootView = AnyView(
            MenuBarRootView(
                model: model,
                chartStyle: chartStyle,
                onOpenSettings: onOpenSettings,
                onDismissPanel: { [weak self] in
                    self?.dismiss()
                }
            )
            .id(sessionID)
        )
    }
}
