# Vercel Web Analytics API Contract

Updated: 2026-08-09

This document records the public API contract that Vercel Analytics Bar may use. The app must not call Vercel dashboard endpoints or infer a contract from dashboard traffic.

## Public endpoints

| Need | Public endpoint | Required parameters |
| --- | --- | --- |
| Validate access token and discover scopes | `GET /v2/teams` | None |
| Read the current user when available | `GET /v2/user` | None |
| Discover teams | `GET /v2/teams` | None |
| Discover projects | `GET /v9/projects` | `teamId` for team-owned projects |
| Summary totals | `GET /v1/query/web-analytics/visits/count` | `projectId`; optional `since`, `until`, `teamId` |
| Time series and dimension breakdowns | `GET /v1/query/web-analytics/visits/aggregate` | `projectId`, `since`, `until`, `by`; optional `teamId`, `filter`, `limit` |

The API uses bearer authentication. Personal projects omit team scope; team projects include `teamId` or `slug`.

The live probe treats successful access to the required team-list endpoint as token validation. A newly created scoped PAT returned `404 not_found` from `GET /v2/user` while a deliberately invalid token returned `403 forbidden`, so the optional user endpoint is recorded for diagnosis but does not gate the required project and Analytics queries.

## Analytics model

The documented visits endpoints expose `pageviews` and `visitors`. Count responses return one total.
Aggregate responses group by one requested dimension. Time dimensions include `hour`, `day`, `week`,
`month`, and `year`; the app's traffic breakdowns use `requestPath` and `referrerHostname`.
Breakdown rows include the dimension label plus both metrics. The app requests five rows, retains the
server's order, and removes empty labels, direct referral markers, and the synthetic `Others` row.

`since` and `until` accept date strings or millisecond timestamps. Vercel includes both ends of the requested interval, then adjusts aggregate results to the requested granularity. The client therefore defines every product range as an explicit half-open UTC interval, sends `endExclusive` to count queries, sends `endExclusive - 1 ms` to aggregate queries, and discards returned points outside `[start, endExclusive)`. The response's echoed query is retained for compatibility, but it must not widen the logical interval used by cards or charts.

Production is the default for visits queries. The app and probe explicitly send
`filter=environment eq 'production'` for breakdowns. The probe also records whether an explicit
Production count matches the default response without storing metric values.

## Live verification

A local probe against an account with both personal and team projects confirmed:

- `GET /v2/user`, `GET /v2/teams`, and personal/team-scoped `GET /v9/projects` returned `200`.
- Both discovery scopes returned nonempty project lists. The account was smaller than one page, so no live pagination cursor was emitted; the probe follows the documented `pagination.next` cursor contract.
- All three visits count and aggregate queries returned `200` with both `visitors` and `pageviews`.
- The default visits count matched an explicit `environment eq 'production'` query for every tested range.
- Responses exposed `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `X-Vercel-Id`.
- A deliberately invalid token returned `403 forbidden` without exposing a credential or response body.

That verification record predates the dimension probes. The current probe additionally queries
`requestPath` and `referrerHostname` for one selected range. Its output records only status, safe
headers, row count, recognized schema keys, and safe echoed query fields; it does not persist paths,
hostnames, metric values, or project identity.

The API does not return a comparison value. V1 obtains the previous period through a second count query and computes the percentage change in Core.

### Range normalization

The product ranges are calculated from the current time in UTC, independent of the Mac's locale or timezone:

| Product range | Logical interval | Aggregate grouping | Expected points |
| --- | --- | --- | --- |
| Last 24 Hours | Current UTC hour plus the preceding 23 hours | `hour` | Exactly 24 hourly buckets |
| Last 7 Days | The previous seven completed UTC days | `day` | Exactly 7 daily buckets |
| Last 30 Days | The previous 30 completed UTC days | `day` | Exactly 30 daily buckets |

The current period's previous comparison is the immediately preceding interval of the same length. Last 24 Hours totals and comparisons are sums of the current and previous hourly series. Last 7/30 Days use count responses as the authoritative card totals, while the chart is filtered to the same completed-day interval. The menu-bar Visitors value always comes from the aligned Last 24 Hours hourly series. Empty series are valid and produce zero aggregate totals.

The public aggregate API can round an inclusive boundary outward, so a request may still return an extra row even after the end is sent one millisecond before `endExclusive`. Filtering timestamps in the client is required to keep the series at exactly 24, 7, or 30 points.

The dashboard's private `/web-analytics/v2` endpoints are deliberately unsupported. They are not part of the public PAT contract and may change without notice; the app uses the documented public endpoints even though 7-day and 30-day values may not exactly match the dashboard.

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
