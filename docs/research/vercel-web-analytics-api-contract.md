# Vercel Web Analytics API Contract

Updated: 2026-08-02

This document records the public API contract that Vercel Analytics Bar may use. The app must not call Vercel dashboard endpoints or infer a contract from dashboard traffic.

## Public endpoints

| Need | Public endpoint | Required parameters |
| --- | --- | --- |
| Validate access token and discover scopes | `GET /v2/teams` | None |
| Read the current user when available | `GET /v2/user` | None |
| Discover teams | `GET /v2/teams` | None |
| Discover projects | `GET /v9/projects` | `teamId` for team-owned projects |
| Summary totals | `GET /v1/query/web-analytics/visits/count` | `projectId`; optional `since`, `until`, `teamId` |
| Time series | `GET /v1/query/web-analytics/visits/aggregate` | `projectId`, `since`, `until`, `by`; optional `teamId` |

The API uses bearer authentication. Personal projects omit team scope; team projects include `teamId` or `slug`.

The live probe treats successful access to the required team-list endpoint as token validation. A newly created scoped PAT returned `404 not_found` from `GET /v2/user` while a deliberately invalid token returned `403 forbidden`, so the optional user endpoint is recorded for diagnosis but does not gate the required project and Analytics queries.

## Analytics model

The documented visits endpoints expose `pageviews` and `visitors`. Count responses return one total, while aggregate responses can group by one time dimension: `hour`, `day`, `week`, `month`, or `year`.

`since` and `until` accept date strings or millisecond timestamps. Vercel includes both ends of the requested interval, then adjusts them to the requested aggregate granularity. The app must use the response's echoed query values as the authoritative range semantics.

Production is the default for visits queries. The probe additionally sends `filter=environment eq 'production'` and records whether it matches the default response without storing metric values.

## Deliberate v1 omissions

- Bounce Rate is documented for the dashboard but is not among the metrics exposed by the public visits endpoints. V1 omits it.
- The public project discovery API does not expose an Analytics-enabled flag. A project remains `Unknown` until an Analytics query provides an available or unavailable result.
- The probe does not induce `429` or transient server errors. It records safe rate-limit, retry, and request-ID headers when they are present on normal requests.
- The probe tests a known-invalid token to record the public `401` shape. It does not manufacture an inaccessible project merely to force `403`.

## Local probe

Run the probe only from an interactive local terminal:

```sh
make probe
```

The script reads `VERCEL_TOKEN` if it is set; otherwise it prompts with hidden terminal input. It never writes the token, project ID, project name, team ID, metric values, or raw response bodies. It writes a sanitized contract record to `.build/vercel-api-probe.json`, which is ignored by Git.

## Sources

- [Query Web Analytics with the API](https://vercel.com/docs/analytics/web-analytics-api), updated 2026-06-26
- [Aggregate page views API reference](https://vercel.com/docs/rest-api/web-analytics/aggregates-page-views), updated 2026-08-02
- [Count page views API reference](https://vercel.com/docs/rest-api/web-analytics/counts-page-views), updated 2026-08-02
