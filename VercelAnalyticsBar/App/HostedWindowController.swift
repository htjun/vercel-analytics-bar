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
