# Azure SQL migration — plan sketch (not started)

**Written:** 15 Aug 2026. **Status:** exploratory only — nothing below has been built.
Trigger: Andy is unhappy with Supabase's per-project cost if Tree Tops Hub is
ever gifted to another park, and wants to know what moving to a managed
MS SQL host (Azure SQL Database) would involve.

## Why Azure over AWS/GCP for MS SQL

AWS RDS for SQL Server and Google Cloud SQL for SQL Server are both
License-Included pricing — no cheap tier exists because the SQL Server
license itself is billed into the hourly rate (realistically $50–150+/mo
minimum, vs $5–20/mo for Azure SQL Serverless which can auto-pause).
Azure SQL Database is Microsoft's own platform and is the only one with a
genuinely low-cost small-database story — plus **elastic pools**, which
matter specifically for the multi-park scenario: one shared pool of
compute can host many small, lightly-used databases (one per park) far
more cheaply than provisioning each separately. This directly answers
the "gift it to another park = another $10–25/mo forever" problem
Supabase's per-project billing creates.

## What's actually integrated with Supabase today (scanned from the real repo, 15 Aug 2026)

`App.jsx` is 3,131 lines but the Supabase integration surface is small:
- Tables read directly via `supabase-js`: `app_data`, `hub_admins`
- RPCs called via raw REST fetch: `get_admin_stats`, `upsert_push_subscription`
- Direct REST insert: `usage_events`
- Edge Functions: `invite-hub-admin`, `send-notice-push`
- Storage: one upload call, to the `info-pdfs` bucket
- Auth: real Supabase Auth (`auth.uid()`), gating `hub_admins` — added in
  v1.14.0, retiring the old shared PIN (see `supabase/05-real-admin-auth.sql`)
- SQL migrations to port: `01, 03, 04, 05, 06, 07` + legacy `setup-admin-pin.sql`

Rewiring the frontend call sites (Phase 4 below) is the *small* part of
this migration. The real cost is standing up services Supabase currently
gives away for free.

## Phase 0 — decisions to make before writing any code

1. **Auth replacement** — the single biggest unknown, bigger than the
   database swap itself. Supabase Auth (magic link + OTP) needs a
   replacement: Entra External ID (Azure's magic-link-capable auth
   service) or a hand-rolled token issuer in an Azure Function. Nothing
   here is a like-for-like port.
2. **API layer** — browsers can't talk to SQL Server directly the way
   they talk to PostgREST. Two options:
   - **Azure Data API Builder (DAB)** — Microsoft's open-source,
     config-driven REST/GraphQL layer over Azure SQL. Closest
     like-for-like replacement for what PostgREST gives Supabase for
     free, including per-entity role-based permissions.
   - **Azure Functions**, hand-written. More control, and needed
     regardless for the two Edge Function equivalents
     (`invite-hub-admin`, `send-notice-push`) — there's a case for using
     Functions for everything rather than splitting between DAB and
     Functions.
3. **Where access control lives** — today RLS + `security definer`
   functions are the real gatekeeper, not app code (see PROJECT-BRIEF.md
   tech stack notes). To keep that safety posture, port policies to SQL
   Server's native `CREATE SECURITY POLICY` (or DAB's permission config)
   rather than moving the logic into API code.
4. **Multi-tenancy shape**, decided now rather than retrofitted later:
   one Azure SQL Server (free to create) + one elastic pool, one
   database per park, same schema. `App.jsx` should take a
   tenant/endpoint config point from day one rather than hardcoding a
   single backend.

## Phase 1 — schema port

Translate the 6 tracked migration files from Postgres to T-SQL:
- `jsonb` → Azure SQL native JSON type (or `NVARCHAR(MAX)` + JSON
  functions, depending on supported version)
- `gen_random_uuid()` → `NEWID()`
- `timestamptz` → `datetimeoffset`
- RLS policy syntax → `CREATE SECURITY POLICY` or DAB permission config

Recreate: `app_data`, `hub_admins`, `usage_events`, `push_subscriptions`,
plus stored-procedure equivalents of `get_admin_stats` and
`upsert_push_subscription`.

## Phase 2 — API layer

- Stand up DAB or Azure Functions in front of Azure SQL.
- Reimplement `get_admin_stats`/`upsert_push_subscription` as stored
  procs exposed through the API layer.
- Port `invite-hub-admin` and `send-notice-push` to Azure Functions
  (Node/TS, reusing the existing web-push logic).
- Reimplement the `info-pdfs` bucket as an Azure Blob Storage container
  + SAS token issuance.

## Phase 3 — auth

- Stand up the chosen auth replacement (Entra External ID or custom).
- Repoint the `hub_admins` gating logic at the new token/session instead
  of `auth.uid()`.

## Phase 4 — frontend rewiring

Swap the `supabase-js` client and the ~9 integration points listed above
to the new API layer. Smallest phase given how contained the surface is.

## Phase 5 — data migration + cutover

Export current `app_data`/`hub_admins`/`usage_events`/`push_subscriptions`
data, transform, load into Azure SQL. Update GitHub Actions
secrets/env vars to point at the new backend.

## Phase 6 — multi-tenant rollout (the actual payoff)

When gifting to a second park: new Azure SQL database in the shared
elastic pool, run the schema migrations against it, add a tenant config
entry. This is the step all of Phase 0's design work is for — it should
be "new database + config entry," not a repeat of Phases 1–5.

## Honest effort/risk read

- **Small:** Phase 4 (touching `App.jsx` itself) — repo scan shows only
  ~9 distinct integration points, not hundreds.
- **Large:** Phases 0–3 — mostly because they're new Azure services to
  learn (DAB or Functions, Entra External ID, Security Policies), not
  because there's much code to port.
- Realistic estimate: a multi-week side-project effort, not a weekend.
  Auth replacement (Phase 3) is the piece most likely to blow the
  estimate.
- Cost payoff only materializes at Phase 6 — i.e., this only pays for
  itself once there's actually a second park, not for the Hub as a
  single-site app today.
