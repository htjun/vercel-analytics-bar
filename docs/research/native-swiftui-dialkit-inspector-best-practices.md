# Native SwiftUI + DialKit Inspector Best Practices

Research snapshot: 2026-08-08

## Scope and evidence rule

This note evaluates a macOS menu-bar application that keeps its production UI native SwiftUI/Swift Charts, while a debug-only inspector window hosts a React/DialKit panel. The platform facts below are sourced only from Apple documentation, the official DialKit repository, and official Vite/React documentation. Repository-specific observations link to this repository's source files.

## Executive recommendation

Use one native macOS process and one debug-only singleton `Window` Scene containing an `NSViewRepresentable` wrapper around `WKWebView`. Load a Vite/DialKit page from a fixed loopback dev server during development, and load the same React build from the app bundle when you need a self-contained debug build. Keep a small, versioned JSON protocol between the page and a main-actor Swift `ChartStyleStore`; validate every incoming message before it can mutate the native chart.

This fits the platform APIs directly: SwiftUI provides a singleton `Window` Scene and the `openWindow` action, `NSViewRepresentable` provides the AppKit-view lifecycle, and WebKit provides the script-message bridge and JavaScript evaluation APIs. [Apple: `Window`](https://developer.apple.com/documentation/swiftui/window) [Apple: `openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) [Apple: `NSViewRepresentable`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable) [Apple: `WKScriptMessageHandler`](https://developer.apple.com/documentation/webkit/wkscriptmessagehandler)

Do not make an external browser plus a custom WebSocket server the first implementation. That adds a second process, a loopback service, port/origin policy, connection lifecycle, and another failure mode even though `WKWebView` already provides the required browser surface inside the native inspector window. This is an architectural recommendation based on the cited APIs, not an Apple-mandated rule. [Apple: `WKWebView`](https://developer.apple.com/documentation/webkit/wkwebview) [Apple: `WKWebView.isInspectable`](https://developer.apple.com/documentation/webkit/wkwebview/isinspectable) [Apple: `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)

## How this repository maps to the recommendation

The current app already uses a SwiftUI `App` entry point, a `MenuBarExtra` with `.menuBarExtraStyle(.window)`, and a `Settings` Scene. That is the correct native base to retain; the inspector should be another Scene in the same `App`, not a second executable. [`VercelAnalyticsBarApp.swift`](../../VercelAnalyticsBar/App/VercelAnalyticsBarApp.swift) [Apple: `MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra) [Apple: Windows and Scenes](https://developer.apple.com/documentation/swiftui/windows)

The chart is already Swift Charts rather than a web chart: the menu-bar view imports `Charts` and uses `Chart`, `AreaMark`, `LineMark`, axis modifiers, a Y-scale, a gradient, a `StrokeStyle`, and a fixed height. The values that should move into a style model are therefore the existing Swift Charts inputs and modifiers, not a replacement chart renderer. [`MenuBarRootView.swift`](../../VercelAnalyticsBar/Features/MenuBar/MenuBarRootView.swift) [Apple: Swift Charts](https://developer.apple.com/documentation/charts) [Apple: `AreaMark`](https://developer.apple.com/documentation/charts/areamark) [Apple: `StrokeStyle`](https://developer.apple.com/documentation/swiftui/strokestyle) [Apple: `AxisMark`](https://developer.apple.com/documentation/charts/axismark)

The existing UI model is `@MainActor @Observable`, which is a good ownership boundary for a mutable chart-style store as well. Keep the style store separate from the analytics-fetching model so that changing a line width never touches refresh, credentials, caching, or Vercel API state. [`AppModel.swift`](../../VercelAnalyticsBar/App/AppModel.swift)

The project targets macOS 14, uses an Xcode app target plus one local Swift package, and currently has no WebKit or web inspector target in the app source/project. That makes a small `Tools/ChartInspector` web project plus a few debug-only Swift bridge files a contained addition. [`Config/Base.xcconfig`](../../Config/Base.xcconfig) [`Packages/VercelAnalyticsCore/Package.swift`](../../Packages/VercelAnalyticsCore/Package.swift) [`VercelAnalyticsBar.xcodeproj/project.pbxproj`](../../VercelAnalyticsBar.xcodeproj/project.pbxproj) [Existing repository research convention](./macos-menubar-tech-stack.md)

The app's `LSUIElement` setting is already enabled, which is the documented way for a menu-bar-only utility to stay out of the Dock and application switcher. A supplemental `Window` Scene is still the right scene-level mechanism for an inspector; the Apple `Window` documentation explicitly describes it as a single unique window that augments an app's main interface. [`Info.plist`](../../VercelAnalyticsBar/SupportingFiles/Info.plist) [Apple: `MenuBarExtra` and `LSUIElement`](https://developer.apple.com/documentation/swiftui/menubarextra) [Apple: `Window`](https://developer.apple.com/documentation/swiftui/window)

## Scene management: use `Window`, not an external launcher

### Why `Window` is the right scene

Use `Window("Chart Inspector", id: "chart-inspector")` for one inspector instance. Apple documents `Window` as a scene with one unique window; calling `openWindow(id:)` orders that window to the front if it is already open. `WindowGroup` is intended for a group of identically structured windows and can create multiple windows, so it is only appropriate if the app later needs one inspector per chart or per preview document. [Apple: `Window`](https://developer.apple.com/documentation/swiftui/window) [Apple: `WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup) [Apple: `openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow)

The scene shape should be approximately:

```swift
@main
@MainActor
struct VercelAnalyticsBarApp: App {
    @State private var model: AppModel
    @State private var chartStyleStore = ChartStyleStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(model: model)
                .environment(chartStyleStore)
        } label: {
            // Existing menu-bar label.
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
        }

        #if DEBUG
        Window("Chart Inspector", id: "chart-inspector") {
            ChartInspectorWindow(styleStore: chartStyleStore)
        }
        #endif
    }
}
```

The exact state-injection syntax can follow the Observation pattern already used by this app. The important boundaries are that the app owns one style store, the menu-bar chart reads it, and the debug window receives the same instance. This is a recommendation for this repository, supported by the existing `@Observable` model and Apple's Scene/window APIs. [`AppModel.swift`](../../VercelAnalyticsBar/App/AppModel.swift) [Apple: Managing model data in SwiftUI](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app) [Apple: Windows](https://developer.apple.com/documentation/swiftui/windows)

Add the open action to a debug-only control in the menu-bar view:

```swift
#if DEBUG
@Environment(\.openWindow) private var openWindow

Button("Open Chart Inspector") {
    openWindow(id: "chart-inspector")
}
#endif
```

`openWindow` is an environment action, and its identifier must match the `Window` or `WindowGroup` identifier declared in the Scene. A duplicate call for this singleton does not create another inspector; it brings the existing window forward. [Apple: `openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) [Apple: `Window`](https://developer.apple.com/documentation/swiftui/window)

No shell script is required to show this window. The web project is a build/runtime dependency of the debug view; window creation itself is managed by SwiftUI. If the window later needs AppKit-only frame or title-bar customization, use the `NSWindow` associated with the SwiftUI-created window or move to an explicit `NSWindowController` only when that requirement is real. `NSView` is the AppKit view infrastructure hosted inside an `NSWindow`, and `NSWindowController` is the AppKit type intended to manage a window's display, closing, title, and frame. [Apple: `NSView`](https://developer.apple.com/documentation/appkit/nsview) [Apple: `NSWindow`](https://developer.apple.com/documentation/appkit/nswindow) [Apple: `NSWindowController`](https://developer.apple.com/documentation/appkit/nswindowcontroller)

## Style ownership and the DialKit contract

### Keep the native style model authoritative

Create a JSON-safe native model whose fields correspond to actual Swift Charts modifiers. For this chart, a first version could contain `lineColor` as a hex string, `lineWidth`, `lineCap`, `lineJoin`, `areaTopOpacity`, `areaBottomOpacity`, `chartHeight`, `axisCount`, `yPaddingPercent`, `showGridLines`, and `showXAxisLabels`. Keep colors and enumerations transport-friendly instead of putting SwiftUI `Color` or `StrokeStyle` directly in the wire model. Swift Charts and SwiftUI accept foreground styles, gradients, and stroke properties at the mark/view boundary, so the renderer can convert the transport model into native types. [Apple: `AreaMark`](https://developer.apple.com/documentation/charts/areamark) [Apple: `foregroundStyle(_:)`](https://developer.apple.com/documentation/swiftui/view/foregroundstyle%28_%3A%29) [Apple: `StrokeStyle`](https://developer.apple.com/documentation/swiftui/strokestyle)

Use a separate `ChartStyleStore` marked `@MainActor` and `@Observable`. The store should expose a validated `ChartStyle`, apply changes synchronously on the main actor, and optionally save a chosen native preset later. The React panel is an editor for this store, not a second renderer and not a second source of truth. This separation is a repository-specific design recommendation based on the existing main-actor `AppModel` and SwiftUI's model-data approach. [`AppModel.swift`](../../VercelAnalyticsBar/App/AppModel.swift) [Apple: Managing model data in SwiftUI](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)

### Use DialKit as a control surface, not as the chart implementation

DialKit's official React API exposes `useDialKit(name, config, options?)`; the hook returns live resolved values, and the controller API additionally exposes `setValue`, `setValues`, `resetValues`, and `getValues`. DialKit supports numeric ranges/steps, booleans, text, colors, selects, nested folders, presets, and JSON copying. [DialKit README](https://github.com/joshpuckett/dialkit/blob/main/README.md) [DialKit `useDialKit` source](https://github.com/joshpuckett/dialkit/blob/main/src/hooks/useDialKit.ts)

Mount one `DialRoot` for the panel. Because this is already a dedicated inspector window, use DialKit's `mode="inline"` so the control surface fills the web view instead of rendering its default floating popover inside a nested browser surface. DialKit documents inline mode for a contained, scrolling panel and documents that `DialRoot` should be mounted once at the app root. [DialKit README](https://github.com/joshpuckett/dialkit/blob/main/README.md)

Use a stable DialKit `id` if the React component can remount during Vite HMR or window reloads. Do not enable DialKit persistence unless browser-local persistence is specifically desired; the official API documents `persist` as storage of values, presets, and the active preset in browser storage. For this inspector, native presets or an explicit JSON export are easier to reason about than silently coupling design values to WebKit website data. [DialKit README](https://github.com/joshpuckett/dialkit/blob/main/README.md)

DialKit is automatically hidden in production builds by default, and `DialRoot` has an explicit `productionEnabled` escape hatch. Still compile the native Scene, bridge, and inspector entry point only for Debug builds; use both defenses so a Release build does not accidentally expose the debug surface. [DialKit README](https://github.com/joshpuckett/dialkit/blob/main/README.md) [Vite: Environment Variables and Modes](https://vite.dev/guide/env-and-mode)

### Recommended protocol

Use a small, versioned protocol rather than sending arbitrary dictionaries directly into the model:

```json
{
  "protocolVersion": 1,
  "type": "styleChanged",
  "source": "chart-inspector",
  "revision": 42,
  "values": {
    "lineColor": "#007AFF",
    "lineWidth": 2.0,
    "areaTopOpacity": 0.24,
    "areaBottomOpacity": 0.03,
    "chartHeight": 140.0,
    "axisCount": 4.0,
    "yPaddingPercent": 10.0,
    "showGridLines": true
  }
}
```

Use these message directions:

1. React sends `ready` after mounting the DialKit controller.
2. Swift sends `state` containing the canonical native style and revision.
3. React applies the canonical state through DialKit's `setValues`.
4. React sends `styleChanged` whenever its resolved values change.
5. Swift validates, deduplicates, applies, and optionally sends an acknowledgement or the canonicalized state back.

The handshake prevents the panel's initial defaults from silently overwriting the app's native style. DialKit's controller API is the documented mechanism for applying a group of values programmatically; the handshake and message names above are an application-level protocol recommendation. [DialKit README](https://github.com/joshpuckett/dialkit/blob/main/README.md)

On the React side, observe the controller's live `values` and derive a stable serialized snapshot before posting it. The official DialKit source computes controller values from its subscribed store state, while React's `useEffect` documentation defines the setup/cleanup model for synchronizing with external systems. A stable serialized dependency and an equality check avoid a bridge post for every React render. This is an implementation inference from the two APIs. [DialKit `useDialKit` source](https://github.com/joshpuckett/dialkit/blob/main/src/hooks/useDialKit.ts) [React: `useEffect`](https://react.dev/reference/react/useEffect)

An illustrative React-side adapter is:

```tsx
import { useEffect } from 'react';
import { useDialKitController } from 'dialkit';

const config = {
  lineColor: '#007AFF',
  lineWidth: [2, 0.5, 8, 0.5],
  areaTopOpacity: [0.24, 0, 1, 0.01],
  areaBottomOpacity: [0.03, 0, 1, 0.01],
  chartHeight: [140, 80, 300, 1],
  axisCount: [4, 2, 10, 1],
  yPaddingPercent: [10, 0, 100, 1],
  showGridLines: true,
};

export function ChartInspector() {
  const controller = useDialKitController('Visitors Chart', config, {
    id: 'vercel-analytics-chart',
  });
  const serializedValues = JSON.stringify(controller.values);

  useEffect(() => {
    window.webkit?.messageHandlers.chartStyle?.postMessage({
      protocolVersion: 1,
      type: 'styleChanged',
      source: 'chart-inspector',
      values: JSON.parse(serializedValues),
    });
  }, [serializedValues]);

  useEffect(() => {
    const applyNativeStyle = (event: Event) => {
      const values = (event as CustomEvent<Record<string, unknown>>).detail;
      controller.setValues(values);
    };

    window.addEventListener('native-chart-style', applyNativeStyle);
    window.webkit?.messageHandlers.chartStyle?.postMessage({
      protocolVersion: 1,
      type: 'ready',
      source: 'chart-inspector',
    });

    return () => {
      window.removeEventListener('native-chart-style', applyNativeStyle);
    };
  }, [controller.setValues]);

  return null;
}
```

Mount `<DialRoot mode="inline" />` once next to this component. The `window.webkit` access is present only when the page is running inside WebKit; the panel can still run in a normal browser for isolated UI work if that access is guarded. DialKit's documented `useDialKitController` methods and React's cleanup semantics support this adapter; the `window.webkit` message name is defined by the native bridge. [DialKit `useDialKit` source](https://github.com/joshpuckett/dialkit/blob/main/src/hooks/useDialKit.ts) [React: `useEffect`](https://react.dev/reference/react/useEffect) [Apple: `WKScriptMessageHandler`](https://developer.apple.com/documentation/webkit/wkscriptmessagehandler)

## `WKWebView` and `NSViewRepresentable` lifecycle

`NSViewRepresentable` is the SwiftUI adapter for an AppKit view. Apple defines separate creation, update, coordinator, and teardown points, and specifically documents `dismantleNSView` for cleanup when the represented view is removed. Use the coordinator as the long-lived delegate/message-handler object; do not create a new web view during every SwiftUI update. [Apple: `NSViewRepresentable`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable) [Apple: `NSViewRepresentableContext`](https://developer.apple.com/documentation/swiftui/nsviewrepresentablecontext) [Apple: `dismantleNSView`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable/dismantlensview%28_%3Acoordinator%3A%29)

Configure the `WKWebViewConfiguration` before creating the `WKWebView`. Apple documents that the configuration carries the `WKUserContentController`, website data store, process pool, scripts, and other settings, and that the configuration is incorporated at web-view initialization rather than changed dynamically afterward. [Apple: `WKWebViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration) [Apple: `WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)

The Swift bridge should have these responsibilities:

```swift
import WebKit
import SwiftUI

struct ChartInspectorWebView: NSViewRepresentable {
    let location: InspectorContentLocation
    let onStyleMessage: (ChartStyleMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStyleMessage: onStyleMessage)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(
            context.coordinator,
            contentWorld: .page,
            name: "chartStyle"
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true // Debug build only.
        context.coordinator.webView = webView
        context.coordinator.load(location, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(location: location, webView: webView)
    }

    static func dismantleNSView(
        _ webView: WKWebView,
        coordinator: Coordinator
    ) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "chartStyle")
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        // Store the latest location, readiness, and last-applied revision here.

        init(onStyleMessage: @escaping (ChartStyleMessage) -> Void) {
            // Store the callback and initialize bridge state.
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Validate name, world, frame, origin, body, schema, and ranges.
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            // Mark ready and send canonical native state to the page.
        }
    }
}
```

The handler is installed in the page content world because the React page calls `window.webkit.messageHandlers.chartStyle.postMessage(...)`. Apple documents both the page-facing JavaScript shape and the content-world-scoped registration API; handler names must be unique within the user content controller and must not be empty. [Apple: `WKScriptMessageHandler`](https://developer.apple.com/documentation/webkit/wkscriptmessagehandler) [Apple: `WKUserContentController.add(_:contentWorld:name:)`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add%28_%3Acontentworld%3Aname%3A%29)

Remove the handler in `dismantleNSView`. Apple documents the matching removal API and says it removes the handler previously installed with `add`; the representable teardown hook is the appropriate place for that cleanup. Stop loading and clear delegates at the same boundary so a closed inspector does not continue receiving navigation callbacks. [Apple: Removing a script message handler](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/removescriptmessagehandler%28forname%3A%29) [Apple: `dismantleNSView`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable/dismantlensview%28_%3Acoordinator%3A%29) [Apple: `WKWebView`](https://developer.apple.com/documentation/webkit/wkwebview)

The `Coordinator` should hold a weak reference to the web view and should not own the `WKWebView` strongly. This avoids a reference cycle through the web view configuration and user-content controller; it is an engineering recommendation for this object graph, not a special WebKit requirement. Apple does document that the user-content controller is the bridge and that the configuration owns that interaction surface. [Apple: `WKWebViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration) [Apple: `WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)

Set `webView.isInspectable = true` only in Debug. Apple documents that the property defaults to `false` and that setting it to `true` enables Safari Web Inspector access; it is useful for inspecting the React/DialKit DOM, CSS, and console without opening the panel in an external browser. [Apple: `WKWebView.isInspectable`](https://developer.apple.com/documentation/webkit/wkwebview/isinspectable)

Use `WKNavigationDelegate` to track `didFinish`, provisional/navigation failures, and web-content-process termination, and to make an allow/cancel decision for every navigation that the inspector could initiate. Apple documents these callbacks and the requirement to call the navigation decision handler when implementing a policy delegate method. [Apple: `WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate) [Apple: navigation action policy](https://developer.apple.com/documentation/webkit/wknavigationactionpolicy) [Apple: navigation policy method](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webview%28_%3Adecidepolicyfor%3Adecisionhandler%3A%29-2ni62)

## Message validation and lifecycle rules

Treat the bridge as an input boundary even though the initial content is local. `WKScriptMessage` exposes the handler name, body, sending frame, web view, and content world; `WKFrameInfo` exposes whether the frame is the main frame, its current request, and its security origin. Use those fields before decoding or applying values. [Apple: `WKScriptMessage`](https://developer.apple.com/documentation/webkit/wkscriptmessage) [Apple: `WKFrameInfo`](https://developer.apple.com/documentation/webkit/wkframeinfo) [Apple: `WKSecurityOrigin`](https://developer.apple.com/documentation/webkit/wksecurityorigin)

The native handler should reject a message unless all of these checks pass:

- `message.name` is exactly `chartStyle`.
- `message.webView` is the coordinator's current web view.
- `message.frameInfo.isMainFrame` is `true`.
- `message.world` is the expected page content world.
- The current location is either the known bundled inspector file URL or the exact loopback development origin and port.
- The body is a JSON object with the expected `protocolVersion`, `type`, and `values` fields.
- Every numeric field is finite and within a declared range; colors match the accepted hex format; enums and booleans are accepted only from a closed set.
- The message type is one of the small set of supported commands, with `styleChanged` the only message allowed to mutate the chart store.

The specific allow-list is an application-level policy derived from the WebKit metadata Apple exposes; Apple does not prescribe these exact validation predicates. Origin checks should use the security-origin protocol/host/port for HTTP development content and the known file location for bundled content. [Apple: `WKScriptMessage`](https://developer.apple.com/documentation/webkit/wkscriptmessage) [Apple: `WKFrameInfo.securityOrigin`](https://developer.apple.com/documentation/webkit/wkframeinfo/securityorigin) [Apple: `WKSecurityOrigin`](https://developer.apple.com/documentation/webkit/wksecurityorigin)

For navigation, allow only the expected inspector location. For a debug server, use one fixed origin such as `http://127.0.0.1:5173` and set Vite to fail if that port is unavailable. For a bundled page, allow only the app's known `file:` URL/read-access directory. Cancel unexpected navigations or route them to an explicitly chosen external handler rather than letting the inspector silently become a general web browser. The allow-list and external-routing behavior are recommendations built on Apple's navigation policy APIs. [Apple: `WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate) [Apple: `WKNavigationActionPolicy`](https://developer.apple.com/documentation/webkit/wknavigationactionpolicy) [Apple: `loadFileURL(_:allowingReadAccessTo:)`](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29)

When Swift sends the canonical style back to React, prefer `callAsyncJavaScript` with structured arguments rather than interpolating JSON into a JavaScript string. Apple documents that the API accepts arguments such as dictionaries, arrays, strings, numbers, dates, and null values, and evaluates in a specified frame/content world. [Apple: `callAsyncJavaScript`](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript%28_%3Aarguments%3Ain%3Acontentworld%3A%29) [Apple: `evaluateJavaScript`](https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript%28_%3Acompletionhandler%3A%29)

An appropriate native-to-web operation is conceptually:

```swift
try await webView.callAsyncJavaScript(
    """
    window.dispatchEvent(
        new CustomEvent('native-chart-style', { detail: style })
    );
    """,
    arguments: ["style": canonicalStyleDictionary],
    in: nil,
    contentWorld: .page
)
```

Only send after `didFinish` and a `ready` message, because SwiftUI view creation and page React mounting are separate lifecycle events. If the page reloads under Vite HMR, clear the ready flag, wait for `didFinish`, and resend the canonical state. If the web-content process terminates, show a recoverable inspector error or reload the debug page. The relevant WebKit lifecycle callbacks are documented by `WKNavigationDelegate`; the ready flag/retry policy is an application-level recommendation. [Apple: `WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate) [React: `useEffect`](https://react.dev/reference/react/useEffect)

## Bundled page versus local dev server

### Development: fixed loopback Vite server

Use a separate web project such as:

```text
Tools/
└── ChartInspector/
    ├── package.json
    ├── vite.config.ts
    └── src/
        ├── main.tsx
        ├── ChartInspector.tsx
        └── bridge.ts
```

Vite's dev server defaults to port `5173`, and Vite documents `server.strictPort` as the option that exits instead of silently moving to another port when the requested port is already in use. A fixed port makes the Swift origin allow-list deterministic. [Vite: Getting Started](https://vite.dev/guide/) [Vite: Server Options](https://vite.dev/config/server-options)

Bind the dev server to loopback, use `strictPort: true`, and avoid broadening Vite's host/CORS policy. Vite documents that its default CORS behavior allows localhost/loopback origins, warns that `server.cors: true` lets any website read the dev server's source/content, and warns against unrestricted allowed hosts. [Vite: Server Options](https://vite.dev/config/server-options)

In Debug, load the explicit URL from Swift, for example `http://127.0.0.1:5173/`. Keep the port and expected origin in one debug-only configuration value. The Vite page can use HMR while the native bridge remains a separate, application-defined script-message channel; do not treat Vite's HMR WebSocket as the native style protocol. Vite documents its development server and its WebSocket server options, but the native message contract above is independent of HMR. [Vite: Getting Started](https://vite.dev/guide/) [Vite: Server Options](https://vite.dev/config/server-options)

### Debug/release builds: bundled static page

Vite's `vite build` produces a bundle suitable for static hosting, with `dist` as the default output directory. Copy that output into a debug resource bundle when you want a self-contained inspector build, then load the bundled `index.html` with `WKWebView.loadFileURL(_:allowingReadAccessTo:)`. Apple documents that the read-access URL can be the file itself or a directory containing related resources; use the `dist` directory as the read-access root so hashed JavaScript and CSS assets can load, while granting no wider directory access. [Vite: Building for Production](https://vite.dev/guide/build) [Vite: Deploying a Static Site](https://vite.dev/guide/static-deploy.html) [Apple: `loadFileURL(_:allowingReadAccessTo:)`](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29)

Use one content-location abstraction in Swift:

```swift
enum InspectorContentLocation {
    case devServer(URL)
    case bundled(indexURL: URL, readAccessURL: URL)
}
```

Debug can select `.devServer` for HMR and `.bundled` for testing the shipped asset shape. Release should not include the Scene, bridge, or inspector resources at all; the Vite `import.meta.env.DEV` constant is also statically replaced at build time and is suitable for dead-code elimination in the web project. Vite documents both the build output and the `DEV`/`PROD` constants. [Vite: Environment Variables and Modes](https://vite.dev/guide/env-and-mode) [Vite: Building for Production](https://vite.dev/guide/build)

If a bundled inspector is used only for developer QA, put its resource-copy phase and Swift files behind the Debug configuration. The current project already separates Debug and Release configurations in the Xcode project and config files, so this can be added as a build-configuration boundary rather than a runtime preference. [`Debug.xcconfig`](../../Config/Debug.xcconfig) [`VercelAnalyticsBar.xcodeproj`](../../VercelAnalyticsBar.xcodeproj/project.pbxproj)

## Is an external browser and WebSocket bridge advisable?

### Default answer: no

The internal `WKWebView` is preferable for this app because it keeps the inspector in the same process and lets Swift connect directly through `WKUserContentController`. Safari Web Inspector can inspect the embedded page when `isInspectable` is enabled, which supplies the browser debugging workflow without making Safari the runtime host. [Apple: `WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller) [Apple: `WKWebView.isInspectable`](https://developer.apple.com/documentation/webkit/wkwebview/isinspectable)

Apple's Foundation API gives the native side a `URLSessionWebSocketTask` for a `ws:` or `wss:` endpoint, with asynchronous send/receive and close operations. It is a WebSocket task/client API; using an external browser would still require a separately managed server endpoint and a protocol around it. The conclusion that this is extra infrastructure for the current app is an architectural inference from the API surface, not a claim that WebSockets are unsuitable in general. [Apple: `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask) [Apple: `URLSession`](https://developer.apple.com/documentation/foundation/urlsession)

### When an external browser becomes justified

Choose a browser/WebSocket bridge only if one of these becomes a real requirement: the inspector must be visible as a separate browser tab, the web control surface must be reused across multiple native apps, a web-only team must iterate without launching the native app, or the inspector must control multiple running app instances. Those are product/workflow decisions, not requirements of Swift Charts or DialKit. If that path is chosen, keep the loopback endpoint bound to `127.0.0.1`, use an unguessable session token, validate the browser origin and session on every message, and close the connection when the app or inspector exits. The validation requirements are security recommendations; Apple documents the WebSocket task and close lifecycle but does not define this application protocol. [Apple: `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask) [Apple: `URLSessionWebSocketTask.cancel(with:reason:)`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask/cancel%28with%3Areason%3A%29)

Do not expose the Vite dev server as the production bridge. Vite's own documentation warns about broad CORS/host settings, and Vite's HMR WebSocket is an implementation detail of the dev server rather than a stable native-app protocol. [Vite: Server Options](https://vite.dev/config/server-options)

## Recommended repository layout

This layout keeps the web tooling separate from the native target while leaving the bridge close to the debug UI:

```text
vercel-analytics-bar/
├── VercelAnalyticsBar/
│   ├── App/
│   │   ├── VercelAnalyticsBarApp.swift
│   │   ├── AppModel.swift
│   │   ├── ChartStyle.swift                 # debug-only at first
│   │   └── ChartStyleStore.swift             # debug-only at first
│   └── Features/
│       ├── MenuBar/
│       │   ├── MenuBarRootView.swift
│       │   ├── ChartInspectorWindow.swift
│       │   └── ChartInspectorWebView.swift
│       └── Settings/
├── Tools/
│   └── ChartInspector/
│       ├── package.json
│       ├── vite.config.ts
│       └── src/
│           ├── main.tsx
│           ├── ChartInspector.tsx
│           └── bridge.ts
└── docs/research/
```

The current repository already uses an app target for platform UI and a local Swift package for core logic, so the inspector should stay in the app target rather than being placed in `VercelAnalyticsCore`. The web project is a development tool; it should not become a production runtime dependency of the core package. [`VercelAnalyticsBar.xcodeproj`](../../VercelAnalyticsBar.xcodeproj/project.pbxproj) [`Packages/VercelAnalyticsCore/Package.swift`](../../Packages/VercelAnalyticsCore/Package.swift) [`macos-menubar-tech-stack.md`](./macos-menubar-tech-stack.md)

## Concise implementation checklist

- [ ] Add a `Codable`, `Equatable` `ChartStyle` transport model whose fields map one-to-one to the current Swift Charts modifiers. [Apple: Swift Charts](https://developer.apple.com/documentation/charts)
- [ ] Add a main-actor `@Observable` `ChartStyleStore`; make the native chart read this store and clamp/reject values at the store boundary. [Apple: Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [ ] Add `Window("Chart Inspector", id: "chart-inspector")` under `#if DEBUG`, and open it with `@Environment(\.openWindow)`. [Apple: `Window`](https://developer.apple.com/documentation/swiftui/window) [Apple: `openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow)
- [ ] Build `Tools/ChartInspector` with React, DialKit, and Vite; mount one `<DialRoot mode="inline" />`. [DialKit README](https://github.com/joshpuckett/dialkit/blob/main/README.md) [Vite: Getting Started](https://vite.dev/guide/)
- [ ] Use `useDialKitController` for live values and `setValues` for native-to-web hydration; post only a versioned `ready`/`styleChanged` protocol. [DialKit `useDialKit` source](https://github.com/joshpuckett/dialkit/blob/main/src/hooks/useDialKit.ts)
- [ ] Wrap `WKWebView` in `NSViewRepresentable`; create the configuration and handler in `makeNSView`, update without reloading in `updateNSView`, and remove handlers/delegates in `dismantleNSView`. [Apple: `NSViewRepresentable`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable) [Apple: `WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)
- [ ] Validate message name, content world, web-view identity, main-frame status, exact content origin/location, protocol version, schema, ranges, and message type before mutating Swift state. [Apple: `WKScriptMessage`](https://developer.apple.com/documentation/webkit/wkscriptmessage) [Apple: `WKFrameInfo`](https://developer.apple.com/documentation/webkit/wkframeinfo) [Apple: `WKSecurityOrigin`](https://developer.apple.com/documentation/webkit/wksecurityorigin)
- [ ] Use `WKNavigationDelegate` to restrict navigation and to handle finish/failure/process-termination states. [Apple: `WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate)
- [ ] Set `isInspectable = true` only in Debug. [Apple: `WKWebView.isInspectable`](https://developer.apple.com/documentation/webkit/wkwebview/isinspectable)
- [ ] Use a fixed loopback Vite URL with `server.host` on loopback and `server.strictPort = true`; do not enable broad CORS or allowed hosts. [Vite: Server Options](https://vite.dev/config/server-options)
- [ ] Test a bundled `dist` build with `loadFileURL(_:allowingReadAccessTo:)`; exclude the inspector Scene, bridge, and resources from Release. [Vite: Building for Production](https://vite.dev/guide/build) [Apple: `loadFileURL`](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29)
- [ ] Prefer the internal `WKWebView`; revisit an external browser/WebSocket bridge only when a separate-browser or multi-process workflow is an explicit requirement. [Apple: `WKWebView`](https://developer.apple.com/documentation/webkit/wkwebview) [Apple: `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)

## Final architecture

```text
MenuBarExtra / Swift Charts
          │ reads
          ▼
@MainActor ChartStyleStore  ◄── validated ChartStyleMessage
          ▲                              ▲
          │ canonical state              │ WKScriptMessageHandler
          │                              │
Debug Window Scene ── NSViewRepresentable ── WKWebView
                                                │
                                      React + DialKit + Vite
```

The recommended first milestone is therefore: native `Window` Scene, internal `WKWebView`, fixed-port Vite development mode, bundled-page smoke test, strict versioned messages, and Debug-only compilation. This delivers the browser-like fine-grained editing workflow while keeping the shipped app's chart and lifecycle native.

## Sources

- [Apple SwiftUI: `MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple SwiftUI: `Window`](https://developer.apple.com/documentation/swiftui/window)
- [Apple SwiftUI: `WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup)
- [Apple SwiftUI: `openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow)
- [Apple SwiftUI: `Windows`](https://developer.apple.com/documentation/swiftui/windows)
- [Apple SwiftUI: `NSViewRepresentable`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)
- [Apple WebKit: `WKWebView`](https://developer.apple.com/documentation/webkit/wkwebview)
- [Apple WebKit: `WKWebViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration)
- [Apple WebKit: `WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)
- [Apple WebKit: `WKScriptMessageHandler`](https://developer.apple.com/documentation/webkit/wkscriptmessagehandler)
- [Apple WebKit: `WKScriptMessage`](https://developer.apple.com/documentation/webkit/wkscriptmessage)
- [Apple WebKit: `WKContentWorld`](https://developer.apple.com/documentation/webkit/wkcontentworld)
- [Apple WebKit: `WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate)
- [Apple WebKit: `WKSecurityOrigin`](https://developer.apple.com/documentation/webkit/wksecurityorigin)
- [Apple WebKit: `loadFileURL(_:allowingReadAccessTo:)`](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl%28_%3Aallowingreadaccessto%3A%29)
- [Apple WebKit: `isInspectable`](https://developer.apple.com/documentation/webkit/wkwebview/isinspectable)
- [Apple Foundation: `URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)
- [Apple AppKit: `NSView`](https://developer.apple.com/documentation/appkit/nsview)
- [Apple AppKit: `NSWindow`](https://developer.apple.com/documentation/appkit/nswindow)
- [Apple AppKit: `NSWindowController`](https://developer.apple.com/documentation/appkit/nswindowcontroller)
- [DialKit official repository README](https://github.com/joshpuckett/dialkit/blob/main/README.md)
- [DialKit official `useDialKit` source](https://github.com/joshpuckett/dialkit/blob/main/src/hooks/useDialKit.ts)
- [React official `useEffect` reference](https://react.dev/reference/react/useEffect)
- [Vite official Getting Started guide](https://vite.dev/guide/)
- [Vite official Build guide](https://vite.dev/guide/build)
- [Vite official Static Deploy guide](https://vite.dev/guide/static-deploy.html)
- [Vite official Server Options](https://vite.dev/config/server-options)
- [Vite official Environment Variables and Modes](https://vite.dev/guide/env-and-mode)
