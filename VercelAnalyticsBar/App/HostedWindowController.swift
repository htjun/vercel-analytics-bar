import AppKit
import SwiftUI

@MainActor
final class HostedWindowController: NSWindowController {
    init(
        title: String,
        contentSize: CGSize,
        minimumContentSize: CGSize? = nil,
        isResizable: Bool = false,
        rootView: some View
    ) {
        var styleMask: NSWindow.StyleMask = [.titled, .closable]
        if isResizable {
            styleMask.formUnion([.miniaturizable, .resizable])
        }

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.contentMinSize = minimumContentSize ?? contentSize
        if !isResizable {
            window.contentMaxSize = contentSize
        }
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
