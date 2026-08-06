-- Tree Tops Hub — actually drop the old open app_data policies
--
-- 05-real-admin-auth.sql tried to drop these as "Public write on
-- app_data" / "Public update on app_data" -- but those are display
-- labels from an earlier report (policy name concatenated with " on
-- <table>" for readability), not the real stored policy names, which
-- are just "Public write" / "Public update". DROP POLICY IF EXISTS
-- silently no-ops on a name that doesn't match, so those wide-open
-- policies (using/check = true, no auth check at all) stayed active
-- this whole time alongside the new restrictive ones -- and since
-- Postgres allows an operation if *any* permissive policy allows it,
-- the old ones alone were enough to let anonymous writes straight
-- through regardless of is_hub_admin(). Confirmed live via
-- pg_policies query, and via a direct anon-key POST that should have
-- been rejected and wasn't.

drop policy if exists "Public write" on public.app_data;
drop policy if exists "Public update" on public.app_data;

-- Also redundant with app_data_select_anon (both select using (true)) --
-- harmless, but tidying up now that we're here.
drop policy if exists "Public read" on public.app_data;
