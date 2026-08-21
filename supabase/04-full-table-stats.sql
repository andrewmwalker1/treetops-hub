-- 04-full-table-stats.sql
--
-- Moves the Admin -> Stats numbers that are supposed to be all-time totals
-- (home-screen install %, game play counts, the four "most called/
-- navigated/visited/form launches" rank lists) out of client-side
-- computation and into get_admin_stats(), alongside active_devices_7d /
-- push_subscribers / heatmap which already work this way.
--
-- Why: App.jsx's loadEvents() fetches usage_events via the REST API,
-- which this project caps at 1000 rows server-side no matter what limit=
-- the client asks for. The stats above were being computed client-side
-- over that capped fetch with no time window at all, so they were never
-- true all-time totals -- just whatever fit in the most recent 1000 rows.
-- Harmless while the table was small, but silently wrong (undercounting,
-- drifting) once usage_events outgrows 1000 rows, same underlying issue
-- as the "Opens (last 7 days)" bug fixed in App.jsx v1.14.1, just for
-- numbers that don't have a time window to mask it behind.
--
-- "Opens (last 7 days)" and "Opens per day" stay client-side (via
-- loadEvents()) since a 7-day window is comfortably under the 1000-row
-- cap at current usage volume and doesn't need this.
--
-- Safe to run on top of 03-device-stats.sql -- purely additive fields on
-- the same json_build_object.

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
    ),
    'opens_total', (
      select count(*) from usage_events where type = 'app_open'
    ),
    'opens_standalone', (
      select count(*) from usage_events where type = 'app_open' and label = 'standalone'
    ),
    'game_plays_whack_a_squirrel', (
      select count(*) from usage_events where type = 'game_play' and label = 'Whack-a-Squirrel'
    ),
    'game_plays_poop_patrol', (
      select count(*) from usage_events where type = 'game_play' and label = 'Poop Patrol'
    ),
    'top_calls', (
      select coalesce(json_agg(json_build_array(label, cnt) order by cnt desc), '[]'::json)
      from (
        select label, count(*) as cnt
        from usage_events
        where type in ('directory_call', 'contractor_call', 'emergency_call')
        group by label
        order by cnt desc
        limit 8
      ) t
    ),
    'top_navs', (
      select coalesce(json_agg(json_build_array(label, cnt) order by cnt desc), '[]'::json)
      from (
        select label, count(*) as cnt
        from usage_events
        where type in ('directory_navigate', 'contractor_navigate', 'emergency_navigate')
        group by label
        order by cnt desc
        limit 8
      ) t
    ),
    'top_websites', (
      select coalesce(json_agg(json_build_array(label, cnt) order by cnt desc), '[]'::json)
      from (
        select label, count(*) as cnt
        from usage_events
        where type in ('directory_website', 'contractor_website')
        group by label
        order by cnt desc
        limit 8
      ) t
    ),
    'top_forms', (
      select coalesce(json_agg(json_build_array(label, cnt) order by cnt desc), '[]'::json)
      from (
        select label, count(*) as cnt
        from usage_events
        where type = 'form_launch'
        group by label
        order by cnt desc
        limit 8
      ) t
    )
  );
$$;

grant execute on function get_admin_stats() to anon;
