# Tree Tops Hub — Claude Code instructions

Read PROJECT-BRIEF.md for full context. This file is the short version:
things to check or do automatically, every session.

## Before doing anything

1. Run `git status` and `git log -1` — confirm you're on a clean, up to
   date `main` before editing anything.
2. Open `App.jsx` and check the `APP_VERSION` constant near the top
   against PROJECT-BRIEF.md's "Last updated" line. If they don't match,
   say so before proceeding — it means something shipped that the brief
   doesn't know about yet, or vice versa.
3. Never trust a filename alone. If something a file contains looks like
   it belongs to a different file (e.g. a `.sql` file containing HTML,
   a `.md` file containing JSON), stop and flag it rather than working
   around it — this has happened before in this project's uploaded
   files and produced a wrong migration.

## Architecture (see PROJECT-BRIEF.md for detail)

- Single-file React app: `App.jsx` (~2,600 lines, intentionally
  monolithic, inline styles, no CSS framework).
- Hosting: GitHub Pages via GitHub Actions on push to `main`. No manual
  build/upload step — just push source.
- Backend: Supabase. Generic `app_data` key/value table, dedicated
  `usage_events` and `push_subscriptions` tables, a `send-notice-push`
  Edge Function, and `info-pdfs` storage bucket.
- No user auth. Anon key is public by design — RLS and
  `security definer` Postgres functions are the real access control,
  not table grants. Follow this pattern for any new write path: don't
  grant the anon key direct table privileges, write through a narrowly
  scoped `security definer` function instead.

## Hard rules — do not violate these

- Every dependency change → regenerate `package-lock.json` in the same
  commit, or the Actions build fails at `npm ci`.
- Static assets (icons etc.) must live in `public/` or Vite silently
  drops them from the build.
- `index.html` must be real source referencing `/main.jsx` — never a
  snapshot of a previously built page.
- Any Supabase RPC/table change: update the matching `.sql` file in the
  repo AND actually run it against the live Supabase project (linked as
  `qkbpsqlrzygcairtidye` — confirm with `supabase link` before any
  `secrets set` or `functions deploy`, there are two projects on this
  account).
- After any change to `App.jsx`: bump `APP_VERSION` and `BUILD_DATE`,
  and update PROJECT-BRIEF.md's "Last updated" line in the same commit.
- Always check `res.ok` and `console.error` on every Supabase `fetch()`
  — silent failures have been a repeated real bug here.
- Test push notifications in a normal (non-Incognito) browser window —
  Chromium blocks the Push API entirely in private mode.

## Current known state

- v1.8.0 in progress: adds a per-device anonymous ID (`getDeviceId()`,
  localStorage), active-user / notification-subscriber / opt-in-rate
  stats, and a busiest-times heatmap to Admin → Stats. Migration file:
  `03-device-stats.sql` — **not yet run against the live database as of
  this writing; confirm before assuming it's applied.**
- That migration reconstructs `upsert_push_subscription` and the
  `push_subscriptions` table shape from how `App.jsx` calls them, since
  the original migration file wasn't available when it was written.
  Diff it against the actual current function definition in the
  Supabase SQL editor before running it, in case column names differ.
- Next feature under consideration: a maintenance/reporting function
  (guest- or staff-facing, not yet scoped).
