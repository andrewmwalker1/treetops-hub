// Supabase Edge Function: hub-send-notice-push
//
// Called from the admin app (Notices tab, "Notify guests" toggle) after a
// new notice is saved. Reads every stored push subscription and sends each
// one a Web Push message via VAPID. Cleans up subscriptions that the push
// service reports as dead (404/410 — the guest uninstalled, revoked
// permission, or the browser rotated the endpoint).
//
// Renamed from "send-notice-push" (Supabase consolidation, 28 Aug 2026):
// the shared project (ozhwgrzlpvfdemmogmav, Maintenance's own) already runs
// a function with that exact name. This function also talks to Postgres
// through the raw REST API rather than supabase-js's createClient(), so
// schema selection is done via the Accept-Profile/Content-Profile headers
// (PostgREST's schema-selection mechanism for direct REST calls) rather
// than a client option.
//
// Deploy with:
//   supabase functions deploy hub-send-notice-push --no-verify-jwt
//
// Required secrets (prefixed HUB_ to avoid colliding with Maintenance's own
// VAPID_* secrets, already set on the shared project):
//   supabase secrets set HUB_VAPID_PUBLIC_KEY=...
//   supabase secrets set HUB_VAPID_PRIVATE_KEY=...
//   supabase secrets set HUB_VAPID_SUBJECT=mailto:you@example.com
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically by
// the Supabase platform — you don't set those yourself.)

import webpush from "npm:web-push@3.6.7";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const { title, body: noticeBody, noticeId } = await req.json();
    if (!title) {
      return new Response(JSON.stringify({ error: "title is required" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const VAPID_PUBLIC_KEY = Deno.env.get("HUB_VAPID_PUBLIC_KEY");
    const VAPID_PRIVATE_KEY = Deno.env.get("HUB_VAPID_PRIVATE_KEY");
    const VAPID_SUBJECT = Deno.env.get("HUB_VAPID_SUBJECT");

    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    // Read every stored subscription. Uses the service_role key, which
    // bypasses RLS — this is the one place in the whole app that's allowed
    // to see the full subscriber list, and it only runs server-side.
    const listRes = await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?select=id,subscription`, {
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        "Accept-Profile": "hub",
      },
    });
    const subscriptions = await listRes.json();

    const payload = JSON.stringify({
      title,
      body: noticeBody || "",
      noticeId,
      url: noticeId ? `/?notice=${noticeId}` : "/",
    });

    let sent = 0;
    let failed = 0;
    const deadIds = [];

    await Promise.all(
      subscriptions.map(async (row) => {
        try {
          await webpush.sendNotification(row.subscription, payload);
          sent++;
        } catch (err) {
          failed++;
          if (err.statusCode === 404 || err.statusCode === 410) {
            deadIds.push(row.id);
          }
        }
      })
    );

    // Clean up subscriptions the push service says are gone for good.
    if (deadIds.length > 0) {
      await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?id=in.(${deadIds.join(",")})`, {
        method: "DELETE",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Profile": "hub",
        },
      });
    }

    return new Response(JSON.stringify({ sent, failed, cleaned: deadIds.length }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
