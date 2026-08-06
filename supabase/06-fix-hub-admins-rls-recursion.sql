-- Tree Tops Hub — fix hub_admins RLS self-reference
--
-- hub_admins_select_self (05-real-admin-auth.sql) checks membership with
-- a raw correlated subquery directly against hub_admins -- a policy ON
-- hub_admins that queries hub_admins to evaluate itself. Postgres can't
-- reliably resolve that self-lookup within the same policy evaluation,
-- so the check silently returns no rows even for a genuinely-listed
-- admin -- exactly what happened testing sign-in just now (a real row
-- existed with a matching id, but the app's post-verify membership
-- check came back empty, showing "this email isn't set up for admin
-- access" incorrectly). Same root cause already documented elsewhere in
-- this project's sister app for RLS self-reference in general: wrap the
-- check in a SECURITY DEFINER function, which runs with the function
-- owner's privileges and so isn't itself subject to the calling
-- session's RLS on the table it reads.

create or replace function public.is_hub_admin()
returns boolean
language sql security definer stable
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.hub_admins where id = auth.uid());
$$;

drop policy if exists hub_admins_select_self on public.hub_admins;
create policy hub_admins_select_self on public.hub_admins
  for select using (public.is_hub_admin());

-- app_data/storage policies reference hub_admins from a *different*
-- table, so they were never subject to the same self-reference problem
-- -- routed through the same function anyway for consistency, so there's
-- exactly one place this check lives.
drop policy if exists app_data_insert_admin on public.app_data;
create policy app_data_insert_admin on public.app_data
  for insert with check (public.is_hub_admin());

drop policy if exists app_data_update_admin on public.app_data;
create policy app_data_update_admin on public.app_data
  for update using (public.is_hub_admin()) with check (public.is_hub_admin());

drop policy if exists info_pdfs_insert_admin on storage.objects;
create policy info_pdfs_insert_admin on storage.objects
  for insert with check (bucket_id = 'info-pdfs' and public.is_hub_admin());
