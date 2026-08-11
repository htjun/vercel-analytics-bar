# Vercel Web Analytics API Contract

Updated: 2026-08-11

This document records the Vercel API behavior used by Vercel Analytics Bar. The Vercel web dashboard is the product source of truth for ranges, summary totals, and comparisons.

## Endpoints

| Need | Endpoint | Required parameters |
| --- | --- | --- |
| Validate access token and discover scopes | `GET /v2/teams` | None |
| Read the current user when available | `GET /v2/user` | None |
| Discover teams | `GET /v2/teams` | None |
| Discover projects | `GET /v9/projects` | `teamId` for team-owned projects |
| Dashboard summary totals | `GET /web-analytics/v2/overview` | `projectId`, `environment`, `filter`, `from`, `to`, `tz`; optional `teamId` |
| Summary totals | `GET /v1/query/web-analytics/visits/count` | `projectId`; optional `since`, `until`, `teamId` |
| Time series and dimension breakdowns | `GET /v1/query/web-analytics/visits/aggregate` | `projectId`, `since`, `until`, `by`; optional `teamId`, `filter`, `limit` |

The API uses bearer authentication. Personal projects omit team scope; team projects include `teamId` or `slug`. Live verification confirmed that the same PAT accepted by the public API also authenticates `/web-analytics/v2/overview` on `api.vercel.com`.

The live probe treats successful access to the required team-list endpoint as token validation. A newly created scoped PAT returned `404 not_found` from `GET /v2/user` while a deliberately invalid token returned `403 forbidden`, so the optional user endpoint is recorded for diagnosis but does not gate the required project and Analytics queries.

## Analytics model

The documented visits endpoints expose `pageviews` and `visitors`. Count responses return one total.
Aggregate responses group by one requested dimension. Time dimensions include `hour`, `day`, `week`,
`month`, and `year`; the app's traffic breakdowns use `requestPath` and `referrerHostname`.
Breakdown rows include the dimension label plus both metrics. The app requests ten candidate rows,
retains the server's order, removes empty labels, direct referral markers, and the synthetic `Others`
row, then keeps the first five remaining rows.

`since` and `until` accept date strings or millisecond timestamps. Vercel includes both ends of the requested interval, then adjusts aggregate results to the requested granularity. The client defines every product range as an explicit half-open interval, sends `endExclusive - 1 ms` to aggregate queries, and discards returned points outside `[start, endExclusive)`. The response's echoed query is retained for compatibility, but it must not widen the logical interval used by charts.

The dashboard overview response exposes `devices` and `total`, which are the authoritative Visitors and Page Views card values. Current requests send `from=start` and `to=endExclusive - 1 ms`. Previous requests use the dashboard's asymmetric inclusive boundaries: `from=previousStart + 1 ms` and `to=currentStart`.

Production is the default for visits queries. The app and probe explicitly send
`filter=environment eq 'production'` for breakdowns. The probe also records whether an explicit
Production count matches the default response without storing metric values.

## Live verification

A local probe against an account with both personal and team projects confirmed:

- `GET /v2/user`, `GET /v2/teams`, and personal/team-scoped `GET /v9/projects` returned `200`.
- Both discovery scopes returned nonempty project lists. The account was smaller than one page, so no live pagination cursor was emitted; the probe follows the documented `pagination.next` cursor contract.
- All three visits count and aggregate queries returned `200` with both `visitors` and `pageviews`.
- Current and previous `/web-analytics/v2/overview` queries returned `200` with `devices` and `total`, and matched the visible dashboard cards.
- The default visits count matched an explicit `environment eq 'production'` query for every tested range.
- Responses exposed `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `X-Vercel-Id`.
- A deliberately invalid token returned `403 forbidden` without exposing a credential or response body.

That verification record predates the dimension probes. The current probe additionally queries
`requestPath` and `referrerHostname` for one selected range. Its output records only status, safe
headers, recognized schema keys, and safe echoed query fields; it does not persist paths, hostnames,
metric values, row counts, or project identity.

The overview API does not return a comparison value. The app obtains the previous period through a second overview query and computes the percentage change in Core.

### Range normalization

The product ranges reproduce the dashboard's client-timezone hour boundaries:

| Product range | Logical interval | Aggregate grouping | Expected points |
| --- | --- | --- | --- |
| Last 24 Hours | Current local hour plus the preceding 23 hours | `hour` | Exactly 24 hourly buckets |
| Last 7 Days | Same local-hour boundary seven calendar days earlier through the end of the current hour | `day` | Up to 8 daily buckets |
| Last 30 Days | Same local-hour boundary 30 calendar days earlier through the end of the current hour | `day` | Up to 31 daily buckets |

The previous comparison is the immediately preceding interval with the same elapsed duration. All card totals and comparisons use overview responses. The menu-bar Visitors value uses a Last 24 Hours overview response even when another card range is selected. Charts and breakdowns remain public aggregate queries over the same current range; an empty series does not replace a valid overview total.

The public aggregate API can round an inclusive boundary outward, so a request may still return an extra row even after the end is sent one millisecond before `endExclusive`. Filtering timestamps in the client is required to keep the series at exactly 24, 7, or 30 points.

`/web-analytics/v2/overview` is an internal dashboard contract and may change without notice. Dashboard parity is the product requirement, so its request and response shape is fixture-tested and must be reverified when Vercel changes it.

## Deliberate v1 omissions

- Bounce Rate is documented for the dashboard but is not among the metrics exposed by the public visits endpoints. V1 omits it.
- The public project discovery API does not expose an Analytics-enabled flag. A project remains `Unknown` until an Analytics query provides an available or unavailable result.
- The probe does not induce `429` or transient server errors. It records safe rate-limit, retry, and request-ID headers when they are present on normal requests.
- The probe tests a known-invalid token and records its safe error metadata. It does not manufacture an inaccessible project merely to force another permission error.
- Live authentication failures currently use `403 forbidden` for a deliberately invalid PAT. Client error mapping must still classify both `401` and `403` according to request context.

## Local probe

Run the probe only from an interactive local terminal:

```sh
make probe
```

The script reads `VERCEL_TOKEN` if it is set; otherwise it prompts with hidden terminal input. It
never writes the token, project ID, project name, team ID, breakdown labels, metric values, or raw
response bodies. It writes a sanitized contract record to `.build/vercel-api-probe.json`, which is
ignored by Git.

## Sources

- [Query Web Analytics with the API](https://vercel.com/docs/analytics/web-analytics-api), updated 2026-06-26
- [Aggregate page views API reference](https://vercel.com/docs/rest-api/web-analytics/aggregates-page-views), updated 2026-08-02
- [Count page views API reference](https://vercel.com/docs/rest-api/web-analytics/counts-page-views), updated 2026-08-02
