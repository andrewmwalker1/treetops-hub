-- Default table grants for the `hub` schema in the shared project
-- (ozhwgrzlpvfdemmogmav). Records what's live -- the original grants were
-- set up during the 28 Aug 2026 consolidation and never saved to this
-- repo; see treetops-maintenance/SUPABASE-CONSOLIDATION-PLAN.md.
--
-- Any table created in `hub` (as postgres, i.e. from the SQL Editor)
-- automatically gets these grants. RLS is still the real access control.
-- Supabase's 30 Oct 2026 change (no more automatic grants on new tables)
-- only affects `public`, so it doesn't touch Hub.
--
-- Checked live 21 Oct 2026: default was anon + authenticated only.
-- The same day, service_role was added so a new table also works from the
-- Edge Functions (invite-hub-admin, hub-send-notice-push), and anon was
-- removed to match CLAUDE.md's rule: the anon key gets no direct table
-- privileges by default. A new table guests need to read directly needs
-- its own `grant select on hub.<table> to anon;`; guest writes go through
-- a `security definer` function instead. Existing tables keep whatever
-- grants they already had -- this only affects tables created from now on.
-- Idempotent.

alter default privileges in schema hub
  grant select, insert, update, delete on tables to authenticated, service_role;

alter default privileges in schema hub
  revoke all on tables from anon;

-- To check:
--   select pg_get_userbyid(defaclrole), defaclacl from pg_default_acl
--   where defaclnamespace = 'hub'::regnamespace and defaclobjtype = 'r';
-- Expect {authenticated=arwd/postgres,service_role=arwd/postgres}
