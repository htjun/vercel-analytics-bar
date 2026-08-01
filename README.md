# Vercel Analytics Bar

Vercel Analytics Bar is a native macOS menu bar application for checking Vercel Analytics at a glance.

The current foundation uses fixture data. It establishes the menu bar experience, a testable data-provider boundary, and repository automation before real Vercel account connection is added.

## Current behavior

- Runs as a menu-bar-only macOS application with no Dock icon.
- Opens a window-style menu bar panel.
- Displays a fixture project name, visitor count, and refresh time.
- Opens a Settings window and terminates from the Quit button.
- Performs no network request and stores no credential.

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

The local `VercelAnalyticsCore` Swift package owns stable analytics domain values and the `AnalyticsSnapshotProviding` boundary. The app injects a fixture provider into a main-actor observable model. A future Vercel API client can replace that provider without changing the menu bar views.

Build configurations are separated into Debug, direct-release, and App Store release variants. Both release variants are currently unsigned build contracts; packaging, signing, notarization, Sparkle, and App Store submission are intentionally deferred.

## Repository map

```text
Config/                         Shared Xcode build settings
Packages/VercelAnalyticsCore/  Domain models, providers, and Core tests
Scripts/                        Bootstrap and verification entry points
VercelAnalyticsBar/             Application composition and SwiftUI features
VercelAnalyticsBarTests/        Main-actor application behavior tests
```

The architecture research behind these decisions is available in `docs/research/macos-menubar-tech-stack.md`.
