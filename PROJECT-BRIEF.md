# Tree Tops Hub — Project Briefing

**Last updated:** 20 Jul 2026 (App.jsx APP_VERSION 1.9.3)

## Who you're talking to

Andy runs Tree Tops Caravan Park (treetops.co.uk), a family-owned holiday
and lodge sales park near Prestatyn/Holywell in North Wales, first
licensed in 1960. Over 65 years of history, multiple Wales in Bloom
awards, a David Bellamy Gold Conservation Award, and 5-star Visit Wales
accreditation. Andy is not a developer — he's hands-on with the business
day to day and picking up technical concepts as needed. Explain things
in plain terms, confirm before anything destructive, and don't assume
prior technical knowledge he hasn't demonstrated.

## What this project is

Tree Tops Hub — a Progressive Web App (PWA) for park guests, live at
**hub.treetops.co.uk**. Guests add it to their phone's home screen (no
App Store). It has five sections: Home, Notices, Forms, Explore (local
businesses), and Contractors — plus a PIN-protected admin portal built
into the app itself, so Andy can manage content without touching code.

## Tech stack & where everything lives

- **Frontend:** React + Vite. The whole app is one component, `App.jsx`
  (large, single-file, flat at the repo root — this is intentional for
  simplicity, not an oversight). PWA support via `vite-plugin-pwa`
  using the `injectManifest` strategy — `sw.js` at the repo root is the
  hand-authored source service worker, not build output.
- **Local repo:** `C:\Users\andy\Documents\GitHub\treetops-hub` — this
  is the real working copy. (A separate, older, git-less copy may exist
  under Downloads from an earlier export; it's stale and not the source
  of truth.)
- **Hosting:** GitHub Pages, custom domain `hub.treetops.co.uk` via a
  `CNAME` file in `public/`. Deploys automatically through a GitHub
  Actions workflow (`.github/workflows/deploy.yml`) on every push to
  `main` — Pages Source is set to **"GitHub Actions"** (not "Deploy from
  a branch" — that distinction caused a real outage once, see History).
- **Repo:** [`andrewmwalker1/treetops-hub`](https://github.com/andrewmwalker1/treetops-hub)
  on GitHub. Andy uses **GitHub Desktop** to push changes — the website's
  manual "Upload files" button doesn't unzip files or handle folders
  reliably and caused a broken deploy previously. Don't suggest it.
- **Database:** Supabase project at `qkbpsqlrzygcairtidye.supabase.co`.
  Core table `app_data` — a simple key/value store (`key text primary
  key`, `value jsonb`). Each key holds one chunk of content as JSON:
  `notices`, `forms`, `directory`, `directoryCategories`, `contractors`,
  `contractorCategories`, `welshWords`, `settings`, `info`, `events`.
  **Most content changes need no database/schema changes at all** —
  new fields just go inside the JSON for their key.
  There are also dedicated `usage_events` and `push_subscriptions`
  tables, a `send-notice-push` Edge Function, and an `info-pdfs` storage
  bucket — these predate this repo's `supabase/` folder and their
  original creation scripts aren't tracked here yet; treat the live
  Supabase schema as authoritative over any local script until that's
  reconciled.
- **SQL migrations:** now tracked in `supabase/` in this repo:
  - `01-app-data-baseline.sql` — creates `app_data` if missing, RLS
    policies, seeds the `events` key. Believed already applied.
  - `setup-admin-pin.sql` — moves the admin PIN from in-app plaintext to
    a hashed, server-checked `verify_admin_pin()` function. **Confirmed
    applied (20 Jul 2026)** — `admin_auth` table and `verify_admin_pin()`
    both exist in the live database.
  - `03-device-stats.sql` — adds `device_id` to `usage_events` and
    `push_subscriptions`, plus a `get_admin_stats()` aggregate RPC for
    the Stats tab (active users, opt-in rate, busiest-times heatmap).
    **Confirmed applied (20 Jul 2026)** — `push_subscriptions.device_id`
    has live data and `get_admin_stats()` exists.
    **Bug found & fixed (20 Jul 2026):** as originally deployed,
    `get_admin_stats()` errored on every call with `22003: integer out
    of range` — the heatmap's 30-day window did `30 * 24 * 60 * 60 *
    1000` as plain integer math (2,592,000,000, over the ~2.147 billion
    int4 limit), which made PostgREST return an error and the app's
    `loadAdminStats()` silently fall back to all zeros (Andy noticed
    "Notification subscribers" looked wrong on the Stats tab — this is
    why: the *whole* RPC was failing, not just that one number). Fixed
    by casting to bigint (`30::bigint * 24 * ...`) — same live-tested,
    re-verified `push_subscribers` now returns 18, matching the real row
    count. The file in this repo has the fix; the live function was
    updated to match via the Supabase SQL editor. Note:
    `upsert_push_subscription` now exists as two overloads (the original
    3-argument version and the new 4-argument `p_device_id` version) —
    Postgres treats differing argument lists as distinct functions
    rather than replacing the old one, as the migration's own comments
    anticipated. Harmless as long as the app calls the 4-arg version,
    but worth tidying up (dropping the old overload) at some point.
  - Admin PIN inside the app (fallback/legacy reference): `1960`
- No user auth beyond the admin PIN. Anon key is public by design — RLS
  and `security definer` Postgres functions are the real access control,
  not table grants. Follow this pattern for any new write path: don't
  grant the anon key direct table privileges, write through a narrowly
  scoped `security definer` function instead.

## Brand identity

Colours pulled directly from the park's logo and defined as the `C`
object at the top of `App.jsx` — deep green `#0B5C38` (primary/wordmark),
bright green `#00AF32` (accent), plus a warm sand/cream palette
(`sand`, `sandDeep`), bark brown, and a gold accent for "featured"
items. Display font is a serif (`displayFont`), body text is system
sans-serif. If branding ever changes, this is the one place to update
it — don't rebuild the theme from scratch.

## Features built so far

- **Notices** — optional start/end dates per notice; only currently-live
  notices show to guests (blank dates = always show). Admin list shows
  Live/Scheduled status.
- **v1.9.0–1.9.3:** Home's featured-notice slot is now a swipeable
  carousel. Admin can star more than one notice (`AdminNotices` no
  longer clears other stars when one is toggled); `getFeaturedNotices()`
  shows every starred active notice, in list order, falling back to
  just the first active notice if none are starred (same as the old
  single-notice behaviour). No tap arrows — guests swipe, or tap a dot
  indicator, regardless of settings; auto-advance timing is
  admin-configurable under Settings → Home featured notices → Carousel
  transition speed (`settings.noticeCarouselSpeed`, seconds, 0 = off),
  stored in the existing `settings` key in `app_data` — no schema
  change needed. The box is fixed at the height of the tallest featured
  notice so it doesn't resize as guests swipe/auto-advance between
  notices of different lengths. **v1.9.2's first attempt at this** used
  a CSS grid stacking trick (`gridArea: "1 / 1"` + `visibility: hidden`)
  — it worked in this session's own Chromium testing but Andy still saw
  the box resizing on his real device. **v1.9.3 replaced it** with a
  JS-measured height instead of relying on the browser's own grid
  track-sizing: every slide renders absolutely positioned/stacked, its
  real height is measured via `ResizeObserver`, and the wrapper is
  pinned to the tallest measured height (`NoticeCarousel` in `App.jsx`).
  If a future device report says it's *still* resizing, suspect the
  service worker serving a stale cached bundle before a genuine layout
  bug — the footer's `APP_VERSION` on the actual device is the fastest
  way to confirm which build is really running.
- **Explore & Contractors** — each entry can have phone (Call button),
  address (Directions button via Google Maps), and website (Website
  button — left blank for Facebook-only businesses).
- **Forms** — links out to MyFormFlow; four forms currently configured.
- **Admin Stats tab** — app opens (7-day chart), % opened from home
  screen vs browser, most-called/most-navigated-to/most-visited-website
  businesses (Explore + Contractors combined), form launch counts.
  v1.8.0 (in progress) adds a per-device anonymous ID (`getDeviceId()`,
  localStorage), active-user / notification-subscriber / opt-in-rate
  stats, and a busiest-times heatmap — see `supabase/03-device-stats.sql`.
- Directory/Contractor category management, Welsh word-of-the-day,
  weather widget, park info section all pre-existing from earlier build
  sessions.

## Development history & lessons learned

- Originally prototyped in an earlier chat with the hillside-horizon
  branding and five-tab structure; that prototype file is the one this
  briefing describes.
- Notice scheduling, contractor websites, and the Stats tab were added
  in a later session, built directly onto the existing file rather than
  reconstructed from scratch, to preserve the exact existing theme.
- Deployment went through several rounds of trial and error:
  1. First attempt: handed over a bare `.jsx` file with no project
     scaffold — doesn't work, there's no `package.json`/entry point for
     a browser or build tool to use.
  2. Vite project scaffold built around it, zipped with a wrapping
     folder — Andy wanted flat files.
  3. Rebuilt fully flat (no folders at all) — but `.github/workflows/`
     and `public/` are **structurally required** by GitHub Actions and
     Vite respectively and can't be flattened away.
  4. First flat zip omitted `package-lock.json`, which broke Netlify/CI
     builds using `npm ci`. Fixed by including it.
  5. Discovered Andy was using GitHub Pages, not Netlify — added
     `.github/workflows/deploy.yml` and a `public/CNAME` file for the
     custom domain, removed the unused `netlify.toml`.
  6. Manual web-upload of files (rather than the zip being properly
     unzipped) left the repo in a mixed state: old PWA/service-worker
     leftovers, a literal un-extracted zip file named "download", and
     — critically — `index.html` ended up containing the plain text
     "hub.treetops.co.uk" (the `CNAME` file's content) instead of real
     HTML, causing a white screen.
  7. GitHub Pages Source was also still set to "Deploy from a branch"
     rather than "GitHub Actions", meaning the Actions build was
     succeeding but being ignored entirely.
  8. Resolved via a full clean restart: wiped the repo, switched to
     GitHub Desktop for pushing files (avoids the unzip/overwrite
     issues), fixed the Pages Source setting. Site has been working
     since.
- **Note (20 Jul 2026):** the repo root currently has some duplicate
  PWA/build-adjacent files alongside `public/` (e.g. a second `CNAME`
  and `apple-touch-icon.png` at root, plus `manifest.webmanifest`,
  `registerSW.js`, `workbox-*.js` at root). `sw.js` at root is genuinely
  source (see Tech stack above); the rest look like leftovers similar to
  the mixed-state incident above and are worth reviewing, but haven't
  been touched — flagging rather than silently cleaning up.
- **Takeaway if something breaks again:** check, in order — (1) GitHub
  Actions tab for a red X, (2) Settings → Pages → Source is "GitHub
  Actions", (3) browser console / view-source for what's actually being
  served, before assuming it's a code problem.

## How to help Andy going forward

- Assume any future file handoffs need to go through GitHub Desktop,
  not the website upload button.
- When making app changes, edit the existing `App.jsx` in place rather
  than regenerating it, to avoid losing the established theme and
  content.
- Content changes (new notices, businesses, forms) generally don't need
  SQL — only genuinely new *types* of data need a script.
- Flag clearly if a change requires a Supabase migration versus just an
  admin-portal edit inside the app itself.
