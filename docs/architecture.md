# Architecture

Analytics Menu Bar concentrates domain rules in six deep modules. Composition code supplies
dependencies and translates module output into presentation state; it does not reproduce their
invariants.

## Dependency direction

```text
App lifecycle and SwiftUI presentation
  -> ProjectCatalog / SnapshotRefreshCoordinator / AnalyticsPanelController
  -> VercelAnalyticsCore public provider and domain boundaries
  -> Vercel public HTTP API

Component Editor adapters
  -> generated Swift and TypeScript contract declarations
  -> Contracts/ComponentEditorContract.json
```

The Core package has no dependency on the application target. The native chart has no dependency on
the Debug-only web Editor. Release configurations compile the shared chart style but exclude the
Editor scene, bridge identity, runtime strings, and web resources.

`AnalyticsSnapshotProviding` is the public Analytics acquisition interface. Overview and aggregate
requests, interval conversion, request fan-out, and response assembly remain inside the Vercel
adapter implementation.

## Domain glossary and ownership

| Term | Owner | Narrow seam | Invariants kept inside |
| --- | --- | --- | --- |
| Analytics range plan | `VercelAnalyticsRange` in `VercelAnalyticsCore` | A selected range, clock date, and client timezone produce current/previous intervals and bucket cadence. | Dashboard-aligned local-hour boundaries, equal elapsed comparison windows, and half-open internal intervals. The Vercel adapter alone converts them to the dashboard overview and public aggregate boundary conventions. |
| Project discovery | `VercelAPIClient` in `VercelAnalyticsCore` | `VercelProjectListingProviding` returns one complete, stable list of accessible projects. | Optional personal scope, team enumeration, cursor pagination and cycle rejection, scope metadata enrichment, team-preferred deduplication, stable ordering, and atomic failure for every attempted scope. |
| Project catalog | `ProjectCatalog` plus the versioned account selection record | Account/project orchestration supplies discovered projects and selection intents; the catalog persists committed selection through `ProjectSelectionPersisting` and exposes reconciled selection and filtered views. | Stable sorting, inaccessible-selection removal, non-empty selection when projects exist, deterministic current fallback, search, duplicate-name metadata, save-before-commit selection transactions, rollback on persistence failure, and legacy migration. |
| Snapshot refresh | `SnapshotRefreshCoordinator` | `SnapshotRefreshRequest` and an `AnalyticsSnapshotProviding` adapter drive one observable `SnapshotRefreshState`. | Coherent content, freshness, messaging, and retry availability; cache-before-live presentation, request identity, coalescing, supersession, cancellation, persistence, stale fallback, retry limits, rate-limit backoff, and one five-minute schedule. |
| Analytics panel | `AnalyticsPanelController` | Status-item code supplies an anchor and owned companion windows, then calls present, dismiss, or teardown. | Session identity, one immutable frame per presentation session, hosted content, initial placement, visibility, highlighting, load task, local/global monitor pair, owned-window rules, transient-child Escape handling, child-first dismissal, and cleanup. |
| Editor contract | `Contracts/ComponentEditorContract.json` | The local generator emits checked-in Swift declarations plus TypeScript declarations and a DialKit field adapter consumed by the native session, browser bridge, and Editor. | Protocol identity, message names, revision bounds, ordered style fields, Editor paths and controls, enum values, defaults, ranges, steps, color syntax, deterministic generation, and stale-output detection. |

## Application composition

`AppModel` owns account connection intent, the selected analytics range, presentation state, and
orchestration between real adapters. It delegates catalog invariants and project-selection
persistence transactions to `ProjectCatalog`, and refresh mechanics to `SnapshotRefreshCoordinator`.
It publishes the coordinator's coherent refresh state for SwiftUI but does not mirror refresh
content, freshness, messaging, or retry availability, and does not keep request IDs, refresh tasks,
retry counters, scheduling loops, or partially persisted project selection.

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

## Component Editor generation and release boundary

Edit `Contracts/ComponentEditorContract.json`, then regenerate both checked-in adapters:

```sh
npm --prefix Tools/ComponentEditor run contract:generate
```

Do not edit these generated files directly:

- `VercelAnalyticsBar/Features/ComponentEditor/Generated/ComponentEditorContract.generated.swift`
- `Tools/ComponentEditor/src/generated/contract.ts`
- `Tools/ComponentEditor/src/generated/component-editor-adapter.ts`

Editor test and build commands run the freshness check before compiling. The Debug build bundles
the generated web application. Direct and App Store release builds must contain neither a
`ComponentEditor` resource directory nor Editor runtime strings; `Scripts/verify.sh` enforces both
conditions.

## Verification boundary

`Scripts/verify.sh` is the repository quality gate. It checks the English-only policy, diff hygiene,
Swift formatting and lint, generated-contract freshness, web behavior and bundle freshness, Core
tests, app tests, Debug resource inclusion, both release builds, and release Editor exclusion.
