# Tree Tops Hub — Project Briefing

**Last updated:** 20 Jul 2026 (App.jsx APP_VERSION 1.9.12)

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
  - `04-info-pdfs-storage.sql` — adds the missing Row Level Security
    policies on `storage.objects` that let the anon key upload PDFs to
    the `info-pdfs` bucket. **Not yet confirmed applied** — written
    21 Jul 2026 in response to Admin → Info's "Upload a PDF" failing
    with `403: new row violates row-level security policy`. Root cause:
    marking a bucket "Public" in the dashboard only allows anonymous
    *reads*; it does not grant anon *uploads* — that's this separate
    policy, which was apparently never created when the `info-pdfs`
    bucket was set up. **This session had no Supabase CLI/credentials
    available to run it directly** (unlike `setup-admin-pin.sql` and
    `03-device-stats.sql` above, which a session with CLI access
    applied and verified) — Andy needs to run this one himself via the
    Supabase SQL Editor. Confirm it actually fixed the upload before
    marking this applied.
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
- **v1.9.0–1.9.12:** Home's featured-notice slot is now a swipeable
  carousel. Admin can star more than one notice (`AdminNotices` no
  longer clears other stars when one is toggled); `getFeaturedNotices()`
  shows every starred active notice, in list order, falling back to
  just the first active notice if none are starred (same as the old
  single-notice behaviour). No tap arrows — guests swipe, or tap a dot
  indicator, regardless of settings; auto-advance timing is
  admin-configurable under Settings → Home featured notices → Carousel
  transition speed (`settings.noticeCarouselSpeed`, seconds, 0 = off),
  stored in the existing `settings` key in `app_data` — no schema
  change needed.

  **⚠ UNRESOLVED — the box-resizing bug (v1.9.2–1.9.12).** The box is
  meant to stay a fixed height (the tallest featured notice) as guests
  swipe/auto-advance between slides. It doesn't, on Andy's phone —
  confirmed for certain via several screen recordings, pixel-measured
  frame by frame (`ffmpeg` + `PIL`/numpy: `crop`/`fps` to extract
  frames, then scan a column of pixels for the card's white background
  to find its top/bottom edge). Left as-is for now, at Andy's request,
  after ~10 attempted fixes across one session. **Do not assume this is
  fixed without a fresh screen recording from Andy** — it has looked
  fixed in this session's own Chromium testing on *every single
  attempt*, and has never once reproduced here.

  Andy's setup: **iPhone 14 Pro Max, iOS 26.5.2**, the Hub added to his
  **Home Screen** (standalone display mode, no Safari address bar) —
  not a plain Safari tab. Confirm this hasn't changed before resuming.

  What's been ruled out, in order tried (each looked correct in this
  session's Chromium testing, each still failed on Andy's phone):
  1. **v1.9.2** — CSS grid stacking (`gridArea:"1/1"` + `visibility:hidden`
     siblings). Grid track sizing should size to the tallest sibling
     regardless of visibility; didn't hold on-device.
  2. **v1.9.3** — `ResizeObserver` measuring the *same* element that also
     got toggled `visibility:hidden`/`visible` for display.
  3. **v1.9.4** — decoupled measurement from display: permanently-hidden
     "prober" copies (never toggled) measured via `ResizeObserver`,
     applied as a fixed `height` to a separate always-visible display
     element.
  4. **v1.9.5** — added an on-screen diagnostic badge
     (`maxH=… idx=… h=[…] w=[…]`) to see React's actual state live.
     **This is where it got interesting:** the badge proved the
     *measurement* was correct and stable (e.g. `h=[141,141,122,141]`,
     correctly distinguishing a shorter 2-line notice from three 3-line
     ones) and `maxH` correctly stayed pinned at the true max
     throughout — yet the box still visibly resized in sync with the
     notice changing.
  5. **v1.9.6** — swapped `visibility:hidden` probes for genuinely
     off-canvas (`left:-9999px`) ones, in case hidden elements weren't
     getting a full layout pass. Identical `maxH` value both before and
     after this change — ruled out visibility-hidden layout timing as
     the cause entirely.
  6. **v1.9.7–1.9.8** — expanded the badge to show `getComputedStyle` and
     `getBoundingClientRect` read *directly off the live DOM*, not just
     React's copy. **The critical finding:** both consistently reported
     the box at its correct fixed height on *every* slide — but
     independent pixel-measurement of the same screen recording showed
     the box genuinely painted at two different real heights depending
     on which slide was showing (e.g. 411px vs 355px, device pixels).
     **The DOM's own layout is correct; the browser just isn't
     repainting to match it.** A real paint/compositing desync, not a
     sizing or measurement bug.
  7. **v1.9.9** — tried forcing React to mount a fresh DOM node per slide
     (`key={notice.id}`) instead of updating one node in place, in case
     of stale paint from an in-place content swap. No change.
  8. **v1.9.10** — researched this properly (see Sources below) and
     applied the standard, documented WebKit fix for `overflow:hidden`
     not reliably re-clipping on content change: forcing the clipping
     element onto its own GPU compositing layer
     (`transform:translateZ(0)` + `will-change:transform`). No change.
  9. **v1.9.11** — tried an *active* forced-repaint nudge (briefly
     perturbing `opacity` on each slide change) rather than a passive
     compositing hint, on the theory that standalone iOS home-screen
     web apps (WKWebView) can skip repainting content changed by JS
     alone. Confirmed still broken on-device.
  10. **v1.9.12** — gave up trying to out-maneuver whatever this is and
      removed the shared ingredient of every attempt above: there is no
      more JS-computed height anywhere. All slides are now always
      mounted, stacked in one CSS grid cell; only `opacity` changes per
      slide. The box's height is pure native grid track-sizing, never
      touched by React state. **This has not been confirmed on Andy's
      phone** — PR merged right as he called it a day for the session,
      before he tested it. **This is the first thing to check when
      picking this back up.**

  Leading theory if v1.9.12 also turns out not to hold: a documented,
  if unconfirmed by the React team, class of **React 18 + Safari bugs**
  where a state-driven update is applied correctly internally but
  doesn't reliably reach the screen in some concurrent-mode edge cases
  (see e.g. facebook/react#22459, #26713 — both closed as stale/
  unconfirmed, both Safari-only, both "state is right, DOM isn't").
  v1.9.12 sidesteps that class of bug by removing state-driven styling
  from the equation rather than working around it, which is a
  meaningfully different bet than v1.9.2 through v1.9.11 — worth
  knowing if it also fails, since it'd suggest the cause is elsewhere
  again (maybe genuinely CSS/compositing after all, or something about
  this specific standalone-PWA/WKWebView context we haven't found yet).

  **Lesson for next time a "looks fine in testing, still broken on the
  real device" bug shows up:** ask for a short screen recording early
  and measure it (`ffmpeg` frame extraction + pixel sampling) rather
  than trusting screenshots or eyeballing — two static screenshots of
  this exact bug looked identical by eye and even pixel-diffed as
  identical in one comparison, because they happened to be two notices
  of coincidentally similar length; only video, measured frame-by-frame,
  proved the resize was real. An on-screen diagnostic badge showing
  live state (then removed once done) was also far more productive
  than guessing blind — it's what turned "measurement must be wrong"
  into "measurement is right, the paint is wrong," which redirected the
  whole investigation.
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
