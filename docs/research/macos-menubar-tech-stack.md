# macOS Menu Bar Tech Stack and Repository Structure

Research snapshot: 2026-08-01

## Executive recommendation

Build Vercel Analytics Bar as a native macOS 14+ application using SwiftUI and a small amount of AppKit only when SwiftUI cannot provide the required status-item behavior.

Use this initial stack:

| Area | Choice |
| --- | --- |
| Language and toolchain | Swift 6 language mode; current stable Xcode 26.x toolchain |
| UI | SwiftUI `MenuBarExtra` with `.window` style; `Settings` scene for onboarding and preferences |
| State | Observation (`@Observable`) on the main actor |
| Concurrency | Structured concurrency, `async`/`await`, actors for refresh and cache coordination |
| Networking | Foundation `URLSession` and `Codable`; no Alamofire |
| Credentials | Security framework / macOS Keychain behind a small `CredentialStore` protocol |
| Preferences | `UserDefaults` / `@AppStorage` for non-secret, low-volume settings |
| Cache | In-memory plus a small versioned Codable file in Application Support; no database in v1 |
| Charts | Swift Charts |
| Logging | Unified Logging through `Logger` from `OSLog`; redact credentials and response bodies |
| Login item | `SMAppService.mainApp` on macOS 13+ |
| Tests | Swift Testing for core and integration tests; XCTest only for UI automation |
| Code quality | SwiftFormat for deterministic formatting and SwiftLint for a small set of semantic rules |
| Project shape | Xcode app target plus one local Swift package containing testable core logic |
| Distribution | Notarized direct beta first; App Store as the easiest mainstream channel; Sparkle only for direct builds |

This is intentionally smaller than CodexBar. CodexBar's SwiftPM-first, multi-target structure is justified by its macOS app, Linux/macOS CLI, widgets, helper processes, and many providers. A Vercel-only app should start with two architectural boundaries—`App` and `Core`—and split further only when an actual feature or distribution target requires it.

## Why native Swift instead of Electron or Tauri

This product is a single-platform utility whose essential capabilities—menu bar presentation, Keychain, charts, login items, sandboxing, signing, and notarization—are all first-party macOS APIs. Native Swift therefore removes an additional runtime, a JavaScript/native bridge, and a second UI framework from a very small application.

Apple provides `MenuBarExtra` specifically for persistent menu bar controls, including a window style for data-rich content. Apple also documents `LSUIElement` for hiding a utility app from the Dock and application switcher. [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

Electron is a reasonable cross-platform choice, but it embeds Chromium and Node.js and uses main/renderer processes plus IPC. That is useful when sharing a substantial web codebase, but it is unnecessary overhead for this macOS-only utility. [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)

Tauri is more attractive than Electron if Windows or Linux becomes a firm requirement because it can reuse a web UI with a Rust host. It still introduces a webview/native boundary and does not improve access to the Apple-only frameworks this product needs. Re-evaluate it only if cross-platform delivery becomes a product requirement rather than a hypothetical future option.

## Primary-source review of recent open-source menu bar apps

The repositories below were inspected at their current default-branch heads on the research date. Commit dates indicate maintenance activity, not architecture quality.

| Project | Inspected head | Relevant structure | Lesson for this project |
| --- | --- | --- | --- |
| [CodexBar](https://github.com/steipete/CodexBar) | `9bb9c42`, 2026-08-01 | SwiftPM package with a core library, macOS app, CLI, replay tools, widgets, helpers, extensive tests and release scripts | Best reference for refresh/data flow, strict concurrency, fixtures, direct distribution, and keeping fetch/parse logic outside UI. Do not copy its target count. |
| [Stats](https://github.com/exelban/stats) | `722f0fe`, 2026-07-30 | Checked-in Xcode project with a shared Kit and separate CPU/RAM/Net/etc. modules and targets | Feature modules are valuable once independent menu items or readers exist. Premature for one Vercel provider. |
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | `2cea363`, 2026-07-26 | Checked-in Xcode project, AppKit lifecycle, explicit `MenuBar`, `Plugin`, `UI`, and `Utility` areas, Sparkle and login-at-launch dependencies | AppKit remains the escape hatch for highly dynamic status items and detachable/custom popovers. It is not required for the initial product. |
| [Ice](https://github.com/jordanbaird/Ice) | `11edd39`, 2025-09-20 | Checked-in Xcode project organized by domain folders (`MenuBar`, `Settings`, `Permissions`, `Updates`, `Utilities`) with Swift packages for focused capabilities | A clear feature-first app folder scales well; keep platform-heavy code in explicit folders instead of hiding it behind generic “manager” layers. |

### CodexBar in detail

CodexBar currently targets macOS 14 and Swift tools 6.2. Its package exposes `CodexBarCore` and a CLI, then adds macOS-only executable targets for the app, widget, and helper tools. It depends on Sparkle for direct updates and enables strict concurrency across targets. [CodexBar `Package.swift`](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/Package.swift)

Its documented data flow is background refresh → provider fetch/probe → shared usage store → menu/icon/widgets, while settings feed refresh cadence and feature flags. This separation is directly applicable to Vercel Analytics Bar. [CodexBar architecture](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/docs/architecture.md)

CodexBar combines a SwiftUI lifecycle and Settings scene with AppKit `NSStatusItem` controllers. Its status-item requirements are unusually complex: multiple providers, dynamically merged icons, custom rendering, and menu-bar visibility recovery. [CodexBar app entry point](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/Sources/CodexBar/CodexbarApp.swift) [CodexBar status-item controller](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/Sources/CodexBar/StatusItemController.swift)

The lesson is not “always use AppKit.” The lesson is to start with SwiftUI's simpler scene API and retain a clean seam where `MenuBarExtra` could later be replaced by an `NSStatusItem` presenter if dynamic icon/layout requirements outgrow it.

CodexBar also demonstrates mature release engineering—format/lint checks, macOS and Linux test jobs, packaging tests, appcast generation, signing, and notarization scripts. That is a useful destination, but most of it solves scale and cross-platform requirements that this repository does not yet have. [CodexBar CI](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/.github/workflows/ci.yml) [CodexBar packaging documentation](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/docs/packaging.md)

### What the other projects confirm

Ice uses a SwiftUI `App` entry point with an AppKit delegate, a conventional checked-in Xcode project, and folders aligned with product/platform capabilities. Its actual menu bar manipulation uses `NSStatusItem` because managing other menu bar items requires lower-level APIs. [Ice app entry point](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Main/IceApp.swift) [Ice control item](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/ControlItem/ControlItem.swift) [Ice Xcode project](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice.xcodeproj/project.pbxproj)

Stats separates independent data readers and menu widgets into feature modules such as CPU, RAM, Network, Battery, and Sensors. Its main app still uses an AppKit application delegate and `NSStatusItem`, reflecting a long-lived application with many separately configurable status items. [Stats source tree](https://github.com/exelban/stats/tree/722f0fe190baf36983ff2cfb93ab6d333b62e44c/Modules) [Stats app delegate](https://github.com/exelban/stats/blob/722f0fe190baf36983ff2cfb93ab6d333b62e44c/Stats/AppDelegate.swift)

SwiftBar has explicit `MenuBar`, `Plugin`, `UI`, and `Utility` areas and directly controls `NSStatusItem` and several `NSPopover` instances. That is appropriate for a plugin host with dynamic menu items, but it would add accidental complexity to a single analytics popover. [SwiftBar source tree](https://github.com/swiftbar/SwiftBar/tree/2cea3635f28da8b2142050c90e1d96754be6113f/SwiftBar) [SwiftBar menu bar item](https://github.com/swiftbar/SwiftBar/blob/2cea3635f28da8b2142050c90e1d96754be6113f/SwiftBar/MenuBar/MenuBarItem.swift)

## Recommended platform baseline

Set the deployment target to macOS 14.

Reasons:

- `MenuBarExtra` already exists on macOS 13, but Observation integration through `@Observable` is available from macOS 14. [Apple: managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- CodexBar and Ice both currently target macOS 14, providing current open-source evidence that this is a practical baseline for actively maintained utilities. [CodexBar package](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/Package.swift) [Ice project](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice.xcodeproj/project.pbxproj)
- It avoids compatibility branches for older state-management and login-item APIs while retaining a wider audience than targeting only the newest macOS release.

Use the current stable Xcode 26.x toolchain in Swift 6 language mode. Do not target Xcode 27 beta for production. Apple lists Xcode 26 as shipping Swift 6.2 and the macOS 26 SDK, while Swift 6.2 adds a more approachable concurrency model. [Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes) [Swift 6.2 release](https://www.swift.org/blog/swift-6.2-released/)

## UI and app lifecycle

Start with:

```swift
@main
struct VercelAnalyticsBarApp: App {
    var body: some Scene {
        MenuBarExtra("Vercel Analytics", systemImage: "chart.line.uptrend.xyaxis") {
            MenuBarRootView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
        }
    }
}
```

Use the window style because the product needs charts, project switching, status/error states, and buttons rather than a short command menu. Apple explicitly describes the window style as suitable for more complex or data-rich menu bar extras. [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

Set `LSUIElement` to hide the Dock icon. Keep a Settings scene so onboarding, account connection, project selection, diagnostics, and privacy explanations have a normal resizable window.

Introduce an AppKit presenter only if one of these becomes a confirmed requirement:

- multiple independent Vercel project icons;
- a status-item label whose width changes continuously;
- custom left/right/middle-click behavior;
- detachable popovers;
- recovery from menu-bar-manager interactions that `MenuBarExtra` cannot handle.

## State and concurrency model

Use a single `@MainActor @Observable` `AppModel` as the UI-facing composition root. It should expose immutable view state and invoke use cases; it should not perform raw network or Keychain operations itself.

Use actors for mutable background state:

- `RefreshCoordinator` actor owns the refresh task, cancellation, retry/backoff, and rate-limit state.
- `AnalyticsCache` actor serializes cache reads and writes.
- `VercelAPIClient` can be an actor or a stateless `Sendable` value backed by an injected `URLSession`.
- UI updates cross to the main actor once a complete snapshot is ready.

Swift's concurrency documentation and Swift 6 strict concurrency support make data-race checking a first-party part of this design. [Apple: Swift concurrency](https://developer.apple.com/documentation/swift/concurrency)

Avoid Combine for new asynchronous pipelines unless an Apple API already exposes a publisher that materially simplifies the implementation. Async functions and `AsyncSequence` are sufficient for refresh events and model updates.

## Networking and Vercel boundary

Use Foundation only:

- `URLSession.data(for:)` for requests;
- endpoint-specific `Codable` request/response types;
- one typed `VercelAPIError` that preserves HTTP status, request ID, rate-limit metadata, and a safe user-facing reason;
- dependency-injected transport so tests can return fixtures without the network;
- explicit `teamId`/scope handling in request builders;
- conservative refresh intervals and conditional backoff for `429` and transient `5xx` responses.

Do not add Alamofire. The API surface is small, authentication is bearer-token based, and Foundation already supplies transport, TLS policy through App Transport Security, caching primitives, and Codable integration. Apple recommends starting with the URL Loading System for secure network communication. [Apple Security overview](https://developer.apple.com/documentation/security/)

Keep Vercel DTOs internal to the API layer. Map them into stable domain models such as `AnalyticsSnapshot`, `Project`, `Team`, `MetricSeries`, and `ConnectionState`. This prevents API payload changes from rippling through SwiftUI views.

## Credentials, preferences, and cache

### Credentials

Store Vercel personal access tokens and future OAuth refresh tokens in Keychain. Wrap the Security framework in a very small `CredentialStore` protocol with production and in-memory implementations. Do not store secrets in `UserDefaults`, SwiftData, logs, crash metadata, or test fixtures. Apple describes Keychain Services as storage for small pieces of sensitive data. [Apple: Keychain Services](https://developer.apple.com/documentation/security/keychain-services)

Avoid a Keychain wrapper dependency in v1. The app needs only save, load, and delete operations for one credential namespace; a focused adapter is easier to audit than another runtime package.

### Preferences

Use `@AppStorage`/`UserDefaults` for non-secret values such as selected project IDs, display mode, refresh interval, and launch-at-login preference. Put preference keys behind one typed namespace to avoid strings spread across views.

### Cache

Start with an in-memory last-known snapshot plus a versioned Codable cache file in the app's Application Support container. This gives fast launch and offline display without introducing migrations or a database.

Do not add SwiftData initially. Apple explicitly supports SwiftData as a cache for remote data, so it is a valid later choice when the product stores queryable long-term history, multiple accounts, or a significant offline dataset. [Apple: SwiftData](https://developer.apple.com/documentation/swiftdata)

## Charts

Use Swift Charts for line, area, and bar charts. It provides native SwiftUI composition, automatic scales and axes, localization, and accessibility without a third-party charting dependency. [Apple: Swift Charts](https://developer.apple.com/documentation/charts)

Keep menu-bar charts intentionally small:

- one primary metric and one comparison in the popover;
- fixed time-range choices such as 24 hours, 7 days, and 30 days;
- aggregate or downsample points before rendering;
- provide textual totals and trends so the chart is not the only representation.

## Login at launch

Use `SMAppService.mainApp.register()` and `unregister()` instead of a third-party launch-at-login package. Apple identifies `SMAppService` as the macOS 13+ replacement for legacy login-item APIs. [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

## Project system decision

### Recommendation: Xcode app target plus a local Swift package

Use a checked-in `.xcodeproj` for the actual application because it makes app-bundle metadata, assets, entitlements, signing, archive/export workflows, App Store submission, and future extensions visible in the standard Apple toolchain.

Put testable non-UI logic in one local package. Swift Package Manager provides products, modules, dependency resolution, build, and test workflows, while Xcode can consume a local package directly. [Swift Package Manager](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/) [Introducing packages](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/introducingpackages/)

Do not start as a pure SwiftPM executable like CodexBar. Pure SwiftPM is attractive for CodexBar because it also ships command-line products on macOS and Linux and has custom scripts that construct the app bundle. That flexibility would make ordinary signing and App Store work less conventional here.

Do not introduce XcodeGen or Tuist on day one. A single app project has little merge pressure, while a project generator adds another tool, manifest, and version to maintain. Reconsider generation if the project gains several extensions, configurations, or frequent project-file merge conflicts.

## Proposed repository layout

```text
vercel-analytics-bar/
├── VercelAnalyticsBar.xcodeproj/
├── VercelAnalyticsBar/
│   ├── App/
│   │   ├── VercelAnalyticsBarApp.swift
│   │   ├── AppEnvironment.swift
│   │   └── AppModel.swift
│   ├── Features/
│   │   ├── MenuBar/
│   │   ├── Onboarding/
│   │   └── Settings/
│   ├── Platform/
│   │   ├── LoginItemController.swift
│   │   └── WorkspaceOpener.swift
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   └── Localizable.xcstrings
│   ├── SupportingFiles/
│   │   ├── Info.plist
│   │   └── VercelAnalyticsBar.entitlements
│   └── PreviewSupport/
├── Packages/
│   └── VercelAnalyticsCore/
│       ├── Package.swift
│       ├── Sources/VercelAnalyticsCore/
│       │   ├── Domain/
│       │   ├── VercelAPI/
│       │   ├── Credentials/
│       │   ├── Refresh/
│       │   └── Cache/
│       └── Tests/VercelAnalyticsCoreTests/
│           ├── Fixtures/
│           ├── VercelAPIClientTests.swift
│           ├── RefreshCoordinatorTests.swift
│           └── AnalyticsMappingTests.swift
├── VercelAnalyticsBarUITests/
├── Config/
│   ├── Debug.xcconfig
│   ├── Release-Direct.xcconfig
│   └── Release-AppStore.xcconfig
├── Scripts/
│   ├── bootstrap.sh
│   └── verify.sh
├── .github/workflows/
│   ├── ci.yml
│   └── release-direct.yml
├── docs/
│   ├── research/
│   └── architecture/
├── .swiftformat
├── .swiftlint.yml
├── Makefile
└── README.md
```

This is a physical organization proposal, not a mandate to create a Swift module for every folder. Start with one core package target. Add separate targets only when they provide an actual dependency boundary, independent product, or meaningful build/test performance benefit.

## Dependency rule

The initial production app should have zero third-party runtime dependencies.

Allowed early dependencies:

- SwiftFormat and SwiftLint as development/CI tools;
- Sparkle 2 only in the direct-distribution configuration.

Every proposed runtime dependency should answer all of these questions before adoption:

1. What Apple/Foundation capability is insufficient?
2. Is the dependency active, signed/tagged, and compatible with Swift 6 strict concurrency?
3. What entitlement, privacy, signing, or update risk does it add?
4. Can it be isolated behind a protocol and removed later?

CodexBar, Ice, and SwiftBar all use Sparkle because they distribute outside the Mac App Store. Sparkle's current setup supports Swift Package Manager and requires extra XPC/entitlement work for sandboxed apps. [Sparkle basic setup](https://sparkle-project.org/documentation/) [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/)

## Tests

Use Swift Testing for core behavior and integration seams. Apple documents direct SwiftPM integration, parameterized tests, concurrency support, and parallel execution. Keep XCTest for UI tests because Apple continues to position XCTest/XCUIAutomation for UI automation. [Apple: Swift Testing](https://developer.apple.com/documentation/testing) [Apple: Xcode testing strategy](https://developer.apple.com/documentation/xcode/testing)

Initial test suite:

- decode representative Vercel user, team, project, visits, aggregate, and error fixtures;
- map API DTOs into stable domain snapshots;
- verify team/project query construction;
- verify `401`, `403`, `429`, and `5xx` behavior;
- verify rate-limit backoff using an injected clock;
- verify cache schema versioning and corrupted-cache recovery;
- verify credentials are never included in descriptions or logs;
- run one UI smoke test for first launch, token validation with a stub transport, project selection, and disconnect.

Use `URLProtocol` or an injected `HTTPTransport` actor for network fixtures. Do not run normal CI against a real Vercel account. Put opt-in live API checks in a separate manual workflow with a narrowly scoped secret.

## Formatting, linting, and CI

Use SwiftFormat as the source of formatting truth and SwiftLint only for rules that catch semantic or maintainability problems rather than restating formatting. Both projects are actively maintained and support command-line/Swift package integration. [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) [SwiftLint](https://github.com/realm/SwiftLint)

Recommended pull-request CI on a pinned macOS image:

1. resolve packages;
2. run SwiftFormat in lint mode;
3. run SwiftLint;
4. run `swift test` for the core package;
5. run `xcodebuild test` for the app scheme with signing disabled;
6. archive an unsigned Release build to catch bundle/configuration failures.

CodexBar and Stats both run macOS CI builds, while CodexBar also shards a much larger SwiftPM test suite. This project does not need sharding initially. [CodexBar CI](https://github.com/steipete/CodexBar/blob/9bb9c42fb6f0484c4d0e398e74393aeb52ac443d/.github/workflows/ci.yml) [Stats build workflow](https://github.com/exelban/stats/blob/722f0fe190baf36983ff2cfb93ab6d333b62e44c/.github/workflows/build.yaml)

## Sandboxing and distribution

Enable App Sandbox from the beginning, including only outgoing network access. This keeps one code path compatible with the Mac App Store and limits the impact of a compromised credential-handling app. Apple requires App Sandbox for Mac App Store distribution and exposes `com.apple.security.network.client` for outbound connections. [Apple: App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) [Apple: configuring App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)

Recommended release sequence:

### Private beta: direct distribution

- Developer ID signing;
- Hardened Runtime;
- App Sandbox;
- notarized and stapled ZIP or DMG;
- GitHub Releases;
- optional Homebrew cask after the artifact and update policy stabilize;
- Sparkle 2 only after the release pipeline is reliable.

Apple requires Developer ID software distributed outside the store to use Hardened Runtime and notarization, and documents `notarytool`/Xcode workflows for automation. [Apple: preparing for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution) [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

### Public release: Mac App Store

- use a separate `Release-AppStore` configuration;
- omit Sparkle and update-feed metadata;
- let the store handle installation and updates;
- retain the same sandboxed API/Keychain architecture.

If both channels remain active, keep channel-specific code behind a tiny `UpdateProviding` interface and compile-time configuration. Do not scatter `#if APP_STORE` checks throughout views.

## Decisions to defer

Do not add these until a concrete requirement appears:

- SwiftData or SQLite;
- a CLI target;
- WidgetKit widgets;
- multiple Swift package modules;
- AppKit status-item management;
- a hosted backend;
- global keyboard-shortcut dependencies;
- analytics/crash-reporting SDKs;
- Xcode project generation;
- Electron/Tauri cross-platform clients.

## Suggested implementation sequence

1. Create the Xcode app target, local core package, sandbox entitlements, and CI build.
2. Add a menu-bar shell with static fixture data and Settings/onboarding windows.
3. Implement typed Vercel API transport and fixture tests.
4. Implement Keychain credential storage and token validation.
5. Add team/project selection and a refresh coordinator with caching/backoff.
6. Add Swift Charts and explicit loading, stale, empty, error, and disconnected states.
7. Add launch-at-login and diagnostics/privacy UI.
8. Produce a signed, notarized beta artifact.
9. Decide between direct-only, App Store-only, or dual-channel distribution based on actual beta feedback.

## Final decision summary

The strongest starting point is not a clone of CodexBar's repository. It is a smaller native architecture informed by CodexBar:

- copy the separation of fetch/parse from UI, strict concurrency, fixture-heavy tests, and disciplined release automation;
- use SwiftUI `MenuBarExtra` before adopting CodexBar's AppKit status-item machinery;
- use a conventional Xcode app target for signing and distribution;
- keep core logic in one local Swift package;
- depend on Apple frameworks for networking, storage, charts, and login items;
- add Sparkle only for a proven direct-distribution channel;
- split targets and modules in response to real products or dependency boundaries, not anticipated complexity.
