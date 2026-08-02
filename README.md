# Vercel Analytics Bar

Vercel Analytics Bar is a native macOS menu bar application for checking Vercel Analytics at a glance.

The application connects directly to Vercel, discovers projects across the account, and shows the selected project's Production Web Analytics. Project switching and refresh coordination remain later milestones.

## Current behavior

- Runs as a menu-bar-only macOS application with no Dock icon.
- Opens a window-style menu bar panel.
- Displays Visitors and Page Views totals with equal-period comparisons after a live API request.
- Switches among Last 24 Hours, Last 7 Days, and Last 30 Days, defaults to Last 7 Days, and persists the selected range.
- Renders the selected range's Visitors trend with a native line and area chart.
- Shows a chart icon and abbreviated Last 24 Hours Visitors count in the menu bar after the first successful load.
- Opens a Settings window and terminates from the Quit button.
- Connects a Vercel Personal Access Token from Settings after validating it with Vercel.
- Restores a validated connection when the menu bar panel or Settings first opens and stores the token only in the macOS Keychain.
- Loads personal and team projects into one searchable, alphabetically sorted Settings list.
- Shows duplicate project names with their team or personal-account metadata and an explicit Analytics status.
- Persists selected project IDs locally, selects the first accessible project when no selection exists, and prevents clearing the final selection.
- Refreshes the project list after account connection or an explicit Settings sync.
- Disconnects by removing the Keychain credential, project preference keys, and analytics cache directory.

The Core client is covered separately by sanitized fixture tests. It supports bearer-authenticated personal and team project discovery, pagination, alphabetical sorting, Production Visitors/Page Views count and time-series queries, equal-period comparisons, and a live ranged snapshot provider for one project. It also provides safe typed handling for authentication, permission, rate-limit, transient, and malformed-response failures. Analytics activation is currently represented as `Unknown` in the project list because the documented public discovery response does not expose that setting; live metric errors are surfaced in the menu bar as unavailable states. Bounce Rate is omitted because the verified public API contract does not provide it.

## Requirements

- macOS 14 or later
- Xcode 16.4 or later with Swift 6 support
- [Homebrew](https://brew.sh/) for development-tool bootstrap

The project currently targets Swift 6 language mode while remaining compatible with the locally validated Xcode 16.4 and Swift 6.1.2 toolchain.

## Bootstrap

Install Mint, SwiftFormat 0.58.5, and SwiftLint 0.59.1:

```sh
make bootstrap
```

Application runtime dependencies remain limited to Apple frameworks. SwiftFormat and SwiftLint are development-only tools pinned in `Mintfile`.

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

The command checks repository language policy, formatting, lint, Core package tests, application tests, and unsigned direct/App Store builds. It requires no Apple signing identity or Vercel account.

For tests without formatting and lint checks, run:

```sh
make test
```

## Architecture

The checked-in Xcode project owns the application bundle, SwiftUI lifecycle, menu bar UI, Settings scene, sandbox metadata, signing configuration, and app tests.

The local `VercelAnalyticsCore` Swift package owns stable analytics domain values, the typed `VercelAPIClient`, project discovery, ranged snapshots, equal-period comparison calculation, and the `AnalyticsSnapshotProviding` boundary. The app injects token-based project and analytics providers into a main-actor observable model, which owns account connection, project selection, persisted range selection, and menu-bar metric state. Fixture providers remain test-only. The API client accepts an injected HTTP transport for deterministic tests; its Vercel DTOs stay internal and tokens or response bodies are never included in client errors. The app's credential boundary uses Security Keychain APIs, while selected project IDs, account preferences, and cache cleanup use an injected account data store so disconnect behavior is testable.

Build configurations are separated into Debug, direct-release, and App Store release variants. Both release variants are currently unsigned build contracts; packaging, signing, notarization, Sparkle, and App Store submission are intentionally deferred.

## Repository map

```text
Config/                         Shared Xcode build settings
Packages/VercelAnalyticsCore/  Domain models, API client, providers, and Core tests
Scripts/                        Bootstrap and verification entry points
VercelAnalyticsBar/             Application composition, Keychain boundary, and SwiftUI features
VercelAnalyticsBarTests/        Main-actor application behavior tests
```

The architecture research behind these decisions is available in `docs/research/macos-menubar-tech-stack.md`.
