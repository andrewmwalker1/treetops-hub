// Tree Tops Hub -- invite a new admin user.
// Called from App.jsx's AdminSettings via a direct fetch to this
// function's URL (this repo has no supabase-js RPC/functions.invoke
// wrapper convention yet, so this matches the existing fetch-based style
// used everywhere else in App.jsx).
//
// Uses the service role deliberately: inviting a user requires the Auth
// Admin API, which the anon key can never call. Because this bypasses
// RLS by design, it re-checks the caller's own hub_admins membership
// itself before doing anything -- the caller must already be a signed-in
// admin (their access token is sent as the Authorization header).

import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { db: { schema: "hub" } }
);

// Called directly from the browser on a different origin than this
// function -- every response (including the OPTIONS preflight) needs
// these headers or the browser blocks the response before the page ever
// sees it.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function callerIsAdmin(req: Request): Promise<boolean> {
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!token) return false;

  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token);
  if (userError || !userData?.user) return false;

  const { data: adminRow } = await supabaseAdmin
    .from("hub_admins")
    .select("id")
    .eq("id", userData.user.id)
    .maybeSingle();

  return !!adminRow;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (!(await callerIsAdmin(req))) {
    return jsonResponse({ error: "Not authorized" }, 403);
  }

  const body = await req.json();
  const { email, displayName } = body;
  if (!email) {
    return jsonResponse({ error: "email is required" }, 400);
  }

  // Without an explicit redirectTo this falls back to the project's Auth
  // Site URL -- which defaulted to Supabase's placeholder
  // http://localhost:3000 until this was noticed (invite links were
  // sending real admins to a localhost address nobody's browser can
  // reach). Site URL has since been corrected too, but pin this
  // explicitly so it can't silently regress if that setting ever
  // changes again.
  const { data: invited, error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
    redirectTo: "https://hub.treetops.co.uk",
  });
  if (inviteError) {
    console.error("inviteUserByEmail failed", inviteError.name, inviteError.status, inviteError.message);
    return jsonResponse({ error: inviteError.message || "Invite failed -- check function logs" }, 400);
  }

  const { error: adminInsertError } = await supabaseAdmin.from("hub_admins").insert({
    id: invited.user.id,
    email,
    display_name: displayName || null,
  });
  if (adminInsertError) {
    return jsonResponse({ error: adminInsertError.message }, 500);
  }

  return jsonResponse({ ok: true });
});
