-- Tree Tops Hub — Supabase setup script
-- Safe to run even if app_data already exists — every step is idempotent.
-- Notices' start/end dates and contractors' website field need no schema
-- changes at all, since they live inside the existing JSON value for the
-- "notices" and "contractors" keys. The only new thing here is the
-- "events" key used for the admin Stats tab.

-- 1. Make sure the table exists in the shape the app expects
create table if not exists public.app_data (
  key text primary key,
  value jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2. Keep updated_at current on every write (handy for debugging/back-ups)
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists app_data_set_updated_at on public.app_data;
create trigger app_data_set_updated_at
  before update on public.app_data
  for each row execute function public.set_updated_at();

-- 3. Row Level Security — allow the app's anon key to read and write.
--    (This matches how notices/forms/etc. already work; re-running is safe.)
alter table public.app_data enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'app_data' and policyname = 'app_data_select_anon'
  ) then
    create policy app_data_select_anon on public.app_data
      for select using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'app_data' and policyname = 'app_data_insert_anon'
  ) then
    create policy app_data_insert_anon on public.app_data
      for insert with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'app_data' and policyname = 'app_data_update_anon'
  ) then
    create policy app_data_update_anon on public.app_data
      for update using (true) with check (true);
  end if;
end $$;

-- 4. Seed the "events" key so the Stats tab has something to read on first
--    load, instead of relying on the app's in-code fallback.
insert into public.app_data (key, value)
values ('events', '[]'::jsonb)
on conflict (key) do nothing;
