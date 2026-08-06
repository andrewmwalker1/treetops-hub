-- Tree Tops Hub — real admin auth (email link + code), replacing the
-- shared PIN.
--
-- Why: the PIN (setup-admin-pin.sql) was a single secret shared by
-- everyone who needed admin access — no per-person accountability, no
-- rate limiting on the verify_admin_pin RPC (a 4-digit PIN behind an
-- unthrottled public function is brute-forceable in well under a
-- minute), and it had to live *somewhere* outside the database to be
-- set up at all, which is exactly how it ended up sitting in a setup
-- script. Also found while building this: app_data's insert/update
-- policies are currently `with check (true)` — completely open to
-- anyone holding the anon key (which is unavoidably public, embedded in
-- the client bundle by design). The PIN was only ever a client-side UI
-- gate in front of that — it never actually stopped a direct REST call
-- with the anon key from writing to app_data. This migration closes
-- that gap for real via RLS, not just the app's own UI.
--
-- Safe to run more than once — every step is idempotent, matching the
-- style of the other files in this folder.

-- 1. hub_admins: the allowlist. Being a real Supabase Auth user is not
--    enough on its own to be treated as an admin (magic-link sign-in
--    will create an auth.users row for literally any email typed into
--    the form) -- every RLS check below requires the signed-in user's
--    id to actually be in this table.
create table if not exists public.hub_admins (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text,
  created_at timestamptz not null default now()
);

alter table public.hub_admins enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'hub_admins' and policyname = 'hub_admins_select_self'
  ) then
    -- Admins can see the full admin list (so an "invite/manage admins"
    -- screen can show who else has access) -- not exposed to anon.
    create policy hub_admins_select_self on public.hub_admins
      for select using (exists (select 1 from public.hub_admins hb where hb.id = auth.uid()));
  end if;
end $$;

-- No insert/update/delete policy on hub_admins on purpose -- the only
-- way onto (or off) this list is through the invite-hub-admin Edge
-- Function, which uses the service role and does its own check that the
-- caller is already an admin before adding anyone.

-- 2. Tighten app_data: guests keep read access (they need to see
--    notices/forms/directory/etc. with no login), but insert/update now
--    require a real signed-in admin instead of "anyone with the anon
--    key". Drops the old fully-open policies and the redundant
--    hand-created ones found sitting alongside them.
drop policy if exists app_data_insert_anon on public.app_data;
drop policy if exists app_data_update_anon on public.app_data;
drop policy if exists "Public write on app_data" on public.app_data;
drop policy if exists "Public update on app_data" on public.app_data;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'app_data' and policyname = 'app_data_insert_admin'
  ) then
    create policy app_data_insert_admin on public.app_data
      for insert with check (exists (select 1 from public.hub_admins hb where hb.id = auth.uid()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'app_data' and policyname = 'app_data_update_admin'
  ) then
    create policy app_data_update_admin on public.app_data
      for update using (exists (select 1 from public.hub_admins hb where hb.id = auth.uid()))
      with check (exists (select 1 from public.hub_admins hb where hb.id = auth.uid()));
  end if;
end $$;

-- 3. Same tightening for the info-pdfs storage bucket -- guests can
--    still read/download PDFs, but only an admin can upload one.
drop policy if exists info_pdfs_insert_anon on storage.objects;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'info_pdfs_insert_admin'
  ) then
    create policy info_pdfs_insert_admin on storage.objects
      for insert with check (
        bucket_id = 'info-pdfs'
        and exists (select 1 from public.hub_admins hb where hb.id = auth.uid())
      );
  end if;
end $$;

-- 4. Retire the PIN system entirely -- superseded by hub_admins above.
--    Nothing else references these, so safe to drop outright.
drop function if exists public.verify_admin_pin(text);
drop table if exists public.admin_auth;
