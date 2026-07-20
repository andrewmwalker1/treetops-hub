-- 03-device-stats.sql
--
-- Adds device-level tracking so Admin → Stats can show:
--   - Active users (distinct devices seen in the last 7 days)
--   - Notification subscribers (count) and opt-in rate
--   - Busiest times heatmap (day-of-week x hour-of-day)
--
-- Safe to run on top of the existing schema — purely additive
-- (new columns are nullable, new function is new).
--
-- IMPORTANT: the "push_subscriptions" table and "upsert_push_subscription"
-- function below are reconstructed from App.jsx's usage of them (this repo's
-- copy of the original migration file wasn't available when this was
-- written). Before running section 2, open your Supabase SQL editor and
-- run `\d push_subscriptions` (or check the table editor) to confirm the
-- real column names match what's referenced here, and pull up the current
-- `upsert_push_subscription` function definition to diff against the
-- CREATE OR REPLACE below — adjust names if anything doesn't line up.

-- =====================================================================
-- 1. usage_events: add device_id
-- =====================================================================
alter table usage_events
  add column if not exists device_id text;

create index if not exists usage_events_device_id_idx on usage_events (device_id);
create index if not exists usage_events_ts_idx on usage_events (ts);

-- =====================================================================
-- 2. push_subscriptions: add device_id, update the upsert function
--    ⚠️ Confirm column/function names against your actual schema first.
-- =====================================================================
alter table push_subscriptions
  add column if not exists device_id text;

create index if not exists push_subscriptions_device_id_idx on push_subscriptions (device_id);

-- Adds p_device_id as a new parameter, defaulting to null so any
-- old cached client build calling the old 3-arg signature still works
-- (Postgres treats this as a distinct overload otherwise — safest is to
-- replace the same signature your current function uses; adjust the
-- CONFLICT target / column list below if your table's unique key or
-- column names differ from what's assumed here).
create or replace function upsert_push_subscription(
  p_endpoint text,
  p_subscription jsonb,
  p_user_agent text,
  p_device_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into push_subscriptions (endpoint, subscription, user_agent, device_id, created_at, last_seen_at)
  values (p_endpoint, p_subscription, p_user_agent, p_device_id, now(), now())
  on conflict (endpoint) do update
    set subscription = excluded.subscription,
        user_agent = excluded.user_agent,
        device_id = coalesce(excluded.device_id, push_subscriptions.device_id),
        last_seen_at = now();
end;
$$;

grant execute on function upsert_push_subscription(text, jsonb, text, text) to anon;

-- =====================================================================
-- 3. Aggregate stats RPC
--
-- Returns only aggregate numbers (counts, grouped counts) — never raw
-- subscriber rows — so it's safe to expose to the anon key, consistent
-- with how push_subscriptions already has no direct anon SELECT access.
-- =====================================================================
create or replace function get_admin_stats()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'push_subscribers', (
      select count(*) from push_subscriptions
    ),
    'active_devices_7d', (
      select count(distinct device_id)
      from usage_events
      where device_id is not null
        and ts >= (extract(epoch from now()) * 1000 - 7 * 24 * 60 * 60 * 1000)
    ),
    'notif_devices_7d', (
      select count(distinct e.device_id)
      from usage_events e
      where e.device_id is not null
        and e.ts >= (extract(epoch from now()) * 1000 - 7 * 24 * 60 * 60 * 1000)
        and exists (
          select 1 from push_subscriptions p where p.device_id = e.device_id
        )
    ),
    'heatmap', (
      -- The 30-day window below needs the ::bigint cast: 30*24*60*60*1000
      -- = 2,592,000,000, which overflows Postgres's plain "integer" type
      -- (max ~2.147 billion) and made the whole function error out with
      -- "22003: integer out of range" — the 7-day windows above stay
      -- under that limit so they didn't show the bug.
      select coalesce(json_agg(row_to_json(t)), '[]'::json)
      from (
        select
          extract(dow from to_timestamp(ts / 1000.0))::int as dow,
          extract(hour from to_timestamp(ts / 1000.0))::int as hour,
          count(*) as count
        from usage_events
        where type = 'app_open'
          and ts >= (extract(epoch from now()) * 1000 - 30::bigint * 24 * 60 * 60 * 1000)
        group by dow, hour
      ) t
    )
  );
$$;

grant execute on function get_admin_stats() to anon;
