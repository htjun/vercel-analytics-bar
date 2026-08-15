#if CHART_INSPECTOR
    import AppKit
    import SwiftUI
    import WebKit

    struct ChartInspectorWebView: NSViewRepresentable {
        let styleStore: ChartStyleStore
        let pageState: ChartInspectorPageState
        let reloadToken: Int

        func makeCoordinator() -> Coordinator {
            Coordinator(
                styleStore: styleStore,
                pageState: pageState,
                source: Result { try ChartInspectorSource.resolve() }
            )
        }

        func makeNSView(context: Context) -> WKWebView {
            let userContentController = WKUserContentController()
            userContentController.add(context.coordinator, contentWorld: .page, name: Coordinator.messageHandlerName)

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = userContentController
            configuration.websiteDataStore = .nonPersistent()

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = context.coordinator
            webView.isInspectable = true
            context.coordinator.webView = webView
            context.coordinator.load(webView, reloadToken: reloadToken)
            return webView
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            context.coordinator.load(webView, reloadToken: reloadToken)
        }

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
            private let pageState: ChartInspectorPageState
            private let source: Result<ChartInspectorSource, any Error>
            private var loadedReloadToken: Int?

            init(
                styleStore: ChartStyleStore,
                pageState: ChartInspectorPageState,
                source: Result<ChartInspectorSource, any Error>
            ) {
                session = ChartInspectorSession(styleStore: styleStore)
                self.pageState = pageState
                self.source = source
            }

            func load(_ webView: WKWebView, reloadToken: Int) {
                guard reloadToken != loadedReloadToken else { return }
                loadedReloadToken = reloadToken
                session.pageWillLoad()
                pageState.startLoading()

                switch source {
                case let .success(source):
                    switch source.kind {
                    case .developmentServer:
                        webView.load(URLRequest(url: source.entryURL))
                    case let .bundled(rootURL):
                        webView.loadFileURL(source.entryURL, allowingReadAccessTo: rootURL)
                    }
                case .failure:
                    pageState.fail("The bundled Inspector resources are missing. Rebuild the web assets and try again.")
                }
            }

            func userContentController(
                _: WKUserContentController,
                didReceive message: WKScriptMessage
            ) {
                guard message.name == Self.messageHandlerName,
                      message.world == .page,
                      message.frameInfo.isMainFrame,
                      message.webView === webView,
                      isExpectedMessageLocation(message)
                else {
                    return
                }

                guard let response = try? session.receive(body: message.body) else { return }
                if let copiedStyleJSON = response.copiedStyleJSON {
                    copyToPasteboard(copiedStyleJSON)
                }
                if response.replaysAnimation {
                    pageState.replayAnimation()
                }
                send(response.state)
            }

            func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation?) {
                session.pageWillLoad()
                pageState.startLoading()
            }

            func webView(_: WKWebView, didFinish _: WKNavigation?) {
                pageState.finishLoading()
            }

            func webView(_: WKWebView, didFail _: WKNavigation?, withError _: any Error) {
                pageState.fail("The Inspector page failed to load. Check the selected mode and try again.")
            }

            func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError _: any Error) {
                pageState
                    .fail(
                        "The Inspector could not connect or load its resources. Check the selected mode and try again."
                    )
            }

            func webViewWebContentProcessDidTerminate(_: WKWebView) {
                session.pageWillLoad()
                pageState.fail("The Inspector web process stopped unexpectedly. Try reloading it.")
            }

            func webView(
                _: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
            ) {
                guard case let .success(source) = source,
                      let url = navigationAction.request.url,
                      source.allowsNavigation(to: url)
                else {
                    decisionHandler(.cancel)
                    return
                }

                decisionHandler(.allow)
            }

            private func isExpectedMessageLocation(_ message: WKScriptMessage) -> Bool {
                guard case let .success(source) = source else { return false }
                let origin = message.frameInfo.securityOrigin
                return source.allowsMessage(
                    frameURL: message.frameInfo.request.url,
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
