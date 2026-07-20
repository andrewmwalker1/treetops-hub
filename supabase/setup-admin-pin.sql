-- One-time setup: run this whole script in the Supabase SQL Editor
-- (Dashboard → your project → SQL Editor → New query → paste → Run).
-- No CLI or Edge Functions needed.
--
-- This stores your PIN as a salted hash (not plain text) in a table that
-- guests can never read directly, and creates a function that checks a
-- submitted PIN against that hash on the server. The browser only ever
-- gets back true or false — never the real PIN.

-- 1. Enable the hashing extension (safe to run even if already enabled).
--    On Supabase this installs into the "extensions" schema, not "public".
create extension if not exists pgcrypto with schema extensions;

-- 2. Table to hold the hashed PIN
create table if not exists admin_auth (
  id int primary key default 1,
  pin_hash text not null
);

-- 3. Set your real PIN here (change '1960' to whatever you want), then run.
--    You can re-run this block any time to change the PIN later.
insert into admin_auth (id, pin_hash)
values (1, extensions.crypt('1960', extensions.gen_salt('bf')))
on conflict (id) do update set pin_hash = excluded.pin_hash;

-- 4. Lock the table down — Row Level Security with no policies means
--    nobody (not even with the anon key) can SELECT/INSERT/UPDATE it
--    directly over the REST API. Only the function below (which runs
--    with elevated "security definer" rights) can read it.
alter table admin_auth enable row level security;

-- 5. The function the app calls. It takes a guessed PIN, hashes it the
--    same way, and returns true/false — the hash itself never leaves
--    the database.
create or replace function verify_admin_pin(pin_attempt text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from admin_auth
    where pin_hash = extensions.crypt(pin_attempt, pin_hash)
  );
$$;

-- 6. Allow the app's anon key to call the function (but not read the table)
grant execute on function verify_admin_pin(text) to anon;
