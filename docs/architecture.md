# Architecture

Vercel Analytics Bar concentrates domain rules in six deep modules. Composition code supplies
dependencies and translates module output into presentation state; it does not reproduce their
invariants.

## Dependency direction

```text
App lifecycle and SwiftUI presentation
  -> ProjectCatalog / SnapshotRefreshCoordinator / AnalyticsPanelController
  -> VercelAnalyticsCore public provider and domain boundaries
  -> Vercel public HTTP API

Chart Inspector adapters
  -> generated Swift and TypeScript contract declarations
  -> Contracts/ChartInspectorContract.json
```

The Core package has no dependency on the application target. The native chart has no dependency on
the Debug-only web Inspector. Release configurations compile the shared chart style but exclude the
Inspector scene, bridge identity, runtime strings, and web resources.

## Domain glossary and ownership

| Term | Owner | Narrow seam | Invariants kept inside |
| --- | --- | --- | --- |
| Analytics range plan | `VercelAnalyticsRange` in `VercelAnalyticsCore` | A selected range, clock date, and client timezone produce current/previous intervals and bucket cadence. | Dashboard-aligned local-hour boundaries, equal elapsed comparison windows, and half-open internal intervals. The Vercel adapter alone converts them to the dashboard overview and public aggregate boundary conventions. |
| Project discovery | `VercelAPIClient` in `VercelAnalyticsCore` | `VercelProjectListingProviding` returns one complete, stable list of accessible projects. | Optional personal scope, team enumeration, cursor pagination and cycle rejection, scope metadata enrichment, team-preferred deduplication, stable ordering, and atomic failure for every attempted scope. |
| Project catalog | `ProjectCatalog` plus the versioned account selection record | Account/project orchestration supplies discovered projects and selection intents; the catalog persists committed selection through `ProjectSelectionPersisting` and exposes reconciled selection and filtered views. | Stable sorting, inaccessible-selection removal, non-empty selection when projects exist, deterministic current fallback, search, duplicate-name metadata, save-before-commit selection transactions, rollback on persistence failure, and legacy migration. |
| Snapshot refresh | `SnapshotRefreshCoordinator` | `SnapshotRefreshRequest` and an `AnalyticsSnapshotProviding` adapter produce `SnapshotRefreshEvent` values. | Cache freshness, cache-before-live presentation, request identity, coalescing, supersession, cancellation, persistence, stale fallback, retry limits, rate-limit backoff, and one five-minute schedule. |
| Analytics panel | `AnalyticsPanelController` | Status-item code supplies an anchor and owned companion windows, then calls present, reposition, dismiss, or teardown. | Session identity, hosted content, placement, visibility, highlighting, load task, local/global monitor pair, owned-window rules, transient-child Escape handling, child-first dismissal, and cleanup. |
| Inspector contract | `Contracts/ChartInspectorContract.json` | The local generator emits checked-in Swift and TypeScript declarations consumed by the native session, browser bridge, and DialKit configuration. | Protocol identity, message names, revision bounds, ordered style fields, enum values, defaults, ranges, steps, color syntax, deterministic generation, and stale-output detection. |

## Application composition

`AppModel` owns account connection intent, the selected analytics range, presentation state, and
orchestration between real adapters. It delegates catalog invariants and project-selection
persistence transactions to `ProjectCatalog`, and refresh mechanics to `SnapshotRefreshCoordinator`.
It publishes module results for SwiftUI but does not keep request IDs, refresh tasks, retry counters,
scheduling loops, or partially persisted project selection.

`StatusBarController` owns the status item and its metric presentation. It delegates the panel's
complete present-to-teardown lifecycle to `AnalyticsPanelController`; it has no event monitor or
outside-click policy of its own.

## Persistence boundaries

- The validated Vercel token is stored through the Keychain credential boundary.
- Selected and current project IDs are one versioned account-selection record. Legacy per-key values
  migrate on first read.
- The selected analytics range remains an account preference.
- Versioned snapshot-cache entries are keyed by project and range under Application Support.
- Disconnect clears credential, account selection/preferences, active refresh state, and snapshot
  cache through their injected boundaries.

## Chart Inspector generation and release boundary

Edit `Contracts/ChartInspectorContract.json`, then regenerate both checked-in adapters:

```sh
npm --prefix Tools/ChartInspector run contract:generate
```

Do not edit either generated file directly:

- `VercelAnalyticsBar/Features/ChartInspector/Generated/ChartInspectorContract.generated.swift`
- `Tools/ChartInspector/src/generated/contract.ts`

Inspector test and build commands run the freshness check before compiling. The Debug build bundles
the generated web application. Direct and App Store release builds must contain neither a
`ChartInspector` resource directory nor Inspector runtime strings; `Scripts/verify.sh` enforces both
conditions.

## Verification boundary

`Scripts/verify.sh` is the repository quality gate. It checks the English-only policy, diff hygiene,
Swift formatting and lint, generated-contract freshness, web behavior and bundle freshness, Core
tests, app tests, Debug resource inclusion, both release builds, and release Inspector exclusion.
