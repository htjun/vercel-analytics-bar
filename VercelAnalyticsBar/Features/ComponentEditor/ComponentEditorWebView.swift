#if COMPONENT_EDITOR
    import AppKit
    import SwiftUI
    import WebKit

    struct ComponentEditorWebView: NSViewRepresentable {
        let styleStore: ComponentStyleStore
        let pageState: ComponentEditorPageState
        let selectedComponent: EditableComponent
        let reloadToken: Int

        func makeCoordinator() -> Coordinator {
            Coordinator(
                styleStore: styleStore,
                pageState: pageState,
                selectedComponent: selectedComponent,
                source: Result { try ComponentEditorSource.resolve() }
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
            context.coordinator.select(selectedComponent)
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
            private let session: ComponentEditorSession
            private let pageState: ComponentEditorPageState
            private let source: Result<ComponentEditorSource, any Error>
            private var loadedReloadToken: Int?

            init(
                styleStore: ComponentStyleStore,
                pageState: ComponentEditorPageState,
                selectedComponent: EditableComponent,
                source: Result<ComponentEditorSource, any Error>
            ) {
                session = ComponentEditorSession(styleStore: styleStore)
                session.select(selectedComponent)
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
                    pageState
                        .fail(
                            "The bundled Component Editor resources are missing. Rebuild the web assets and try again."
                        )
                }
            }

            func select(_ component: EditableComponent) {
                guard session.selectedComponent != component else { return }
                session.select(component)
                guard session.isReady else { return }
                send(session.stateMessage)
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
                if let component = response.replayedComponent {
                    pageState.replayAnimation(for: component)
                }
                if let numberPreviewValue = response.numberPreviewValue {
                    pageState.setNumberPreviewValue(numberPreviewValue)
                    return
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
                pageState.fail("The Component Editor page failed to load. Check the selected mode and try again.")
            }

            func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError _: any Error) {
                pageState
                    .fail(
                        "The Component Editor could not connect or load its resources. "
                            + "Check the selected mode and try again."
                    )
            }

            func webViewWebContentProcessDidTerminate(_: WKWebView) {
                session.pageWillLoad()
                pageState.fail("The Component Editor web process stopped unexpectedly. Try reloading it.")
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

            private func send(_ state: ComponentEditorStateMessage) {
                guard let webView, let payload = try? state.jsonObject() else { return }

                Task { @MainActor in
                    _ = try? await webView.callAsyncJavaScript(
                        "window.__componentEditorReceiveState?.(message)",
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
