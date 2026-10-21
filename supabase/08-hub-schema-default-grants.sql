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
-- service_role was added the same day so a new table also works from the
-- Edge Functions (invite-hub-admin, hub-send-notice-push). Idempotent.

alter default privileges in schema hub
  grant select, insert, update, delete on tables to anon, authenticated;

alter default privileges in schema hub
  grant select, insert, update, delete on tables to service_role;

-- To check:
--   select pg_get_userbyid(defaclrole), defaclacl from pg_default_acl
--   where defaclnamespace = 'hub'::regnamespace and defaclobjtype = 'r';
-- Expect {anon=arwd/postgres,authenticated=arwd/postgres,service_role=arwd/postgres}
