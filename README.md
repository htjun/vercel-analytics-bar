# Vercel Analytics Bar

Vercel Analytics Bar is a native macOS menu bar application for checking Vercel Analytics at a glance.

The application connects directly to Vercel, discovers projects across the account, and shows the selected project's Production Web Analytics. The current project can be switched from the menu bar.

## Current behavior

- Runs as a menu-bar-only macOS application with no Dock icon.
- Opens a window-style menu bar panel.
- Displays Visitors and Page Views totals with equal-period comparisons after a live API request.
- Switches among Last 24 Hours, Last 7 Days, and Last 30 Days, defaults to Last 7 Days, and persists the selected range.
- Renders the selected range's Visitors trend with a native line and area chart.
- Shows the five highest-traffic Production pages by page views and switches locally to the five
  highest-traffic referral hostnames without another request.
- Provides a Debug-only Chart Inspector for live tuning the native chart with DialKit controls.
- Shows a chart icon and abbreviated Last 24 Hours Visitors count in the menu bar after the first successful load.
- Opens a Settings window and terminates from the Quit button or Command-Q.
- Includes an independent chart app icon and a monochrome chart menu-bar icon.
- Connects a Vercel Personal Access Token from Settings after validating it with Vercel.
- Restores a validated connection when the menu bar panel or Settings first opens and stores the token only in the macOS Keychain.
- Loads personal and team projects into one searchable, alphabetically sorted Settings list.
- Shows duplicate project names with their team or personal-account metadata and an explicit Analytics status.
- Persists selected project IDs locally, selects the first accessible project when no selection exists, and prevents clearing the final selection.
- Opens a searchable menu-bar project selector containing only selected projects, persists the current project, and shows a cached snapshot immediately while the new project refreshes.
- Links the current project and selected range to its detailed Vercel Analytics dashboard.
- Refreshes the current project every five minutes, skips popover-open requests while data is under one minute old, and coalesces duplicate refreshes.
- Persists versioned snapshots under Application Support, keeps stale data visible through transient failures, and applies Vercel rate-limit backoff with bounded manual retries.
- Refreshes the project list after account connection or an explicit Settings sync.
- Disconnects by removing the Keychain credential, project preference keys, and analytics cache directory.
- Offers an off-by-default Open at login setting through macOS Login Items.
- States that the app is independent and not affiliated with Vercel; credentials are sent directly to Vercel and are not operated by a hosted Vercel Analytics Bar service.

The Core client is covered separately by sanitized fixture tests. It supports bearer-authenticated
personal and team project discovery, pagination, alphabetical sorting, dashboard-aligned Production
Visitors/Page Views totals, time-series, page-path, and referral-hostname queries, comparisons, and a
live ranged snapshot provider for one project. It also provides safe typed handling for
authentication, permission, rate-limit, transient, and malformed-response failures. Analytics
activation is currently represented as `Unknown` in the project list because the documented public
discovery response does not expose that setting; live metric errors are surfaced in the menu bar as
unavailable states. Bounce Rate is omitted because the verified public API contract does not
provide it.

### Analytics range semantics

Analytics windows follow the Vercel dashboard in the Mac's current timezone and are represented internally as half-open intervals: `[start, endExclusive)`. Last 24 Hours includes the current local hour and the preceding 23 hourly buckets. Last 7 Days and Last 30 Days start at the same local-hour boundary seven or 30 calendar days earlier and run through the end of the current hour. The immediately preceding comparison uses the same elapsed duration.

Cards and the menu-bar Visitors value use the same bearer-authenticated `/web-analytics/v2/overview` endpoint as the Vercel dashboard. Current overview requests send `from=start` and `to=endExclusive - 1 ms`; previous requests reproduce the dashboard's `from=previousStart + 1 ms` and `to=currentStart` boundaries. Visitors come from `devices`, Page Views come from `total`, and Core calculates the displayed percentage from the two overview responses.

Charts and breakdowns continue to use the public aggregate endpoint with the dashboard-aligned range. Vercel's web dashboard is the product source of truth, so exact dashboard card parity takes precedence over relying exclusively on the documented public visits endpoints. The overview endpoint is an internal Vercel contract and must be reverified if Vercel changes it.

## Requirements

- macOS 14 or later
- Xcode 26 or later with Swift 6 support
- [Homebrew](https://brew.sh/) for development-tool bootstrap
- Node.js 20.16 or later for Chart Inspector development and verification

The project targets Swift 6 language mode and keeps a macOS 14 deployment target. Xcode 26 is required so the custom AppKit menu-bar panel uses native Liquid Glass when the app runs on macOS 26 while retaining the standard system material on macOS 14 through macOS 25.

## Bootstrap

Install Node.js, Mint, SwiftFormat 0.58.5, and SwiftLint 0.59.1, then restore the locked Inspector
dependencies:

```sh
make bootstrap
```

Application runtime dependencies remain limited to Apple frameworks. SwiftFormat and SwiftLint are
development-only tools pinned in `Mintfile`; React, DialKit, and Vite are Debug Inspector tooling
pinned by `Tools/ChartInspector/package-lock.json`.

## Open and run

Build and launch the application directly from Terminal:

```sh
make run
```

The app appears as a chart icon in the macOS menu bar and does not appear in the Dock. Use its Quit button before running the command again.

To work in Xcode, open the checked-in project and run the shared `VercelAnalyticsBar` scheme:

```sh
make open
```

The Debug configuration uses the temporary development bundle identifier `com.jasonjun.VercelAnalyticsBar`. A final identifier and Apple Developer Team are required only before distribution.

## Tune the chart

The normal application launch keeps development controls out of the menu-bar panel:

```sh
make run
```

To use the self-contained bundled Inspector without Node.js or a running development server, opt in
explicitly:

```sh
make run-inspector-bundled
```

Then open the menu-bar panel and choose **Chart Inspector**. Repeating the action brings the existing
Inspector window forward.

The Inspector controls line color, width, cap, and join; area opacities; chart height; axis density;
Y-scale headroom; and grid/X/Y label visibility. Changes are applied immediately to Swift Charts
without refreshing analytics. **Reset to defaults** restores the code-defined style, and **Copy
canonical JSON** copies the validated native state.

For React/DialKit hot reload, use two terminals:

```sh
# Terminal 1
make inspector-dev

# Terminal 2
make run-inspector
```

Development mode accepts only `http://127.0.0.1:5173`. Stop any running copy of the app before
switching between normal, bundled Inspector, and hot-reload modes. To regenerate the committed
self-contained assets after changing the web project, run:

```sh
make inspector-build
```

Inspector protocol and chart-style declarations are generated from
`Contracts/ChartInspectorContract.json`. After changing that contract, regenerate the checked-in
Swift and TypeScript declarations before rebuilding the web assets:

```sh
npm --prefix Tools/ChartInspector run contract:generate
make inspector-build
```

Inspector-enabled builds set `WKWebView.isInspectable`, so the embedded page can also be inspected
from Safari's Develop menu. Direct and App Store release configurations omit the Inspector scene,
bridge, and web resources.

## Probe the public API

To verify the public Vercel API contract with a local account:

```sh
make probe
```

The command uses a Vercel access token from `VERCEL_TOKEN` when available, or prompts with hidden terminal input. It does not persist the token, raw API responses, project identifiers, names, or metric values. The resulting sanitized capability record is written to `.build/vercel-api-probe.json`.

## Verify

Run the complete local quality gate:

```sh
make verify
```

The command checks repository language policy, formatting, lint, web tests and bundle freshness,
Core package tests, application tests, the Debug Inspector bundle, unsigned direct/App Store builds,
and Inspector exclusion from release artifacts. It requires no Apple signing identity or Vercel
account.

For tests without formatting and lint checks, run:

```sh
make test
```

## Architecture

The checked-in Xcode project owns the application bundle, AppKit lifecycle, menu bar UI, hosted SwiftUI
Settings and Debug-only Chart Inspector windows, WebKit bridge, Login Items integration, asset catalog,
sandbox metadata, signing configuration, and app tests.

The local `VercelAnalyticsCore` Swift package owns stable analytics domain values, canonical UTC
range plans, the typed `VercelAPIClient`, project discovery, ranged snapshots, equal-period
comparison calculation, and the `AnalyticsSnapshotProviding` boundary. The main-actor application
model owns account and range intent plus presentation orchestration. It delegates catalog and
selection invariants to `ProjectCatalog`, refresh/cache/concurrency/retry/scheduling mechanics to
`SnapshotRefreshCoordinator`, and the complete menu-bar panel lifecycle to
`AnalyticsPanelController`. Fixture providers remain test-only. The API client accepts an injected
HTTP transport for deterministic tests; its Vercel DTOs stay internal and tokens or response bodies
are never included in client errors.

The app's credential boundary uses Security Keychain APIs. Selected and current project IDs are one
versioned persisted record with legacy migration; account preferences and versioned snapshot cache
use injected stores so disconnect and recovery behavior are testable. Snapshot cache entries are
keyed by project and analytics range and are persisted under Application Support; corrupt or
incompatible files are discarded. The Chart Inspector's language-neutral JSON contract generates
the Swift and TypeScript declarations used by both adapters, and freshness is checked before every
Inspector test or build.

The complete ownership map and domain glossary are in
[`docs/architecture.md`](docs/architecture.md).

Build configurations are separated into Debug, direct-release, and App Store release variants. Both release variants are currently unsigned build contracts; packaging, signing, notarization, Sparkle, and App Store submission are intentionally deferred.

## Repository map

```text
Config/                         Shared Xcode build settings
Contracts/                      Authoritative language-neutral generated-code contracts
Packages/VercelAnalyticsCore/  Domain models, API client, providers, and Core tests
Scripts/                        Bootstrap and verification entry points
Tools/ChartInspector/           Generated contract, React, DialKit, Vite, and bridge tests
VercelAnalyticsBar/             Application composition, Keychain boundary, and SwiftUI features
VercelAnalyticsBarTests/        Main-actor application behavior tests
```

The architecture research behind these decisions is available in `docs/research/macos-menubar-tech-stack.md`.
