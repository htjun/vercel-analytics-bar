#if CHART_INSPECTOR
    import AppKit
    import SwiftUI
    import WebKit

    struct ChartInspectorWebView: NSViewRepresentable {
        let styleStore: ChartStyleStore

        func makeCoordinator() -> Coordinator {
            Coordinator(styleStore: styleStore)
        }

        func makeNSView(context: Context) -> WKWebView {
            let userContentController = WKUserContentController()
            userContentController.add(context.coordinator, contentWorld: .page, name: Coordinator.messageHandlerName)

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = context.coordinator
            webView.isInspectable = true
            context.coordinator.webView = webView
            webView.load(URLRequest(url: ChartInspectorLocation.developmentURL))
            return webView
        }

        func updateNSView(_: WKWebView, context _: Context) {}

        static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: Coordinator.messageHandlerName,
                contentWorld: .page
            )
            coordinator.webView = nil
        }

        @MainActor
        final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
            static let messageHandlerName = "chartStyle"

            weak var webView: WKWebView?
            private let session: ChartInspectorSession

            init(styleStore: ChartStyleStore) {
                session = ChartInspectorSession(styleStore: styleStore)
            }

            func userContentController(
                _: WKUserContentController,
                didReceive message: WKScriptMessage
            ) {
                guard message.name == Self.messageHandlerName,
                      message.world == .page,
                      message.frameInfo.isMainFrame,
                      message.webView === webView,
                      isExpectedOrigin(message.frameInfo.securityOrigin)
                else {
                    return
                }

                guard let response = try? session.receive(body: message.body) else { return }
                if let copiedStyleJSON = response.copiedStyleJSON {
                    copyToPasteboard(copiedStyleJSON)
                }
                send(response.state)
            }

            func webView(
                _: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
            ) {
                if navigationAction.request.url == ChartInspectorLocation.developmentURL {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                }
            }

            private func isExpectedOrigin(_ origin: WKSecurityOrigin) -> Bool {
                ChartInspectorLocation.allows(
                    scheme: origin.protocol,
                    host: origin.host,
                    port: origin.port
                )
            }

            private func send(_ state: ChartInspectorStateMessage) {
                guard let webView, let payload = try? state.jsonObject() else { return }

                Task { @MainActor in
                    _ = try? await webView.callAsyncJavaScript(
                        "window.__chartInspectorReceiveState?.(message)",
                        arguments: ["message": payload],
                        in: nil,
                        contentWorld: .page
                    )
                }
            }

            private func copyToPasteboard(_ value: String) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }
#endif
