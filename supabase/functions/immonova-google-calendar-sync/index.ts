// Supabase Edge Function: immonova-google-calendar-sync
// Legge da Google Calendar quali fasce orarie sono occupate nei prossimi 60 giorni,
// PER OGNI utente che ha collegato Google Calendar (immonova_calendar_connections,
// provider='google'). Rinnova automaticamente l'access_token quando scaduto usando il
// refresh_token salvato. Le fasce vengono salvate in immonova_calendar_busy_blocks con
// user_id + provider='google'.
// Da schedulare ogni 5-10 minuti via Supabase Cron, come icloud-calendar-sync.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID");
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET");
const SYNC_DAYS_AHEAD = 60;

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function ensureFreshAccessToken(supabase: any, conn: any): Promise<string> {
  const expiresAt = conn.google_token_expires_at ? new Date(conn.google_token_expires_at).getTime() : 0;
  const stillValid = expiresAt - Date.now() > 60000; // margine di 1 minuto
  if (stillValid && conn.google_access_token) return conn.google_access_token;

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    throw new Error("GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET non configurati tra i secret.");
  }
  if (!conn.google_refresh_token) {
    throw new Error("Nessun refresh_token salvato: l'utente deve ricollegare Google Calendar.");
  }

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      refresh_token: conn.google_refresh_token,
      grant_type: "refresh_token",
    }),
  });
  const json = await res.json();
  if (!res.ok) {
    throw new Error("Rinnovo token Google fallito: " + (json.error_description || json.error || res.status));
  }

  const newExpiresAt = new Date(Date.now() + (json.expires_in || 3600) * 1000).toISOString();
  await supabase.from("immonova_calendar_connections").update({
    google_access_token: json.access_token,
    google_token_expires_at: newExpiresAt,
  }).eq("id", conn.id);

  return json.access_token;
}

async function syncOneConnection(supabase: any, conn: any, timeMin: string, timeMax: string) {
  try {
    const accessToken = await ensureFreshAccessToken(supabase, conn);
    const calendarId = encodeURIComponent(conn.google_calendar_id || "primary");
    const params = new URLSearchParams({
      timeMin, timeMax, singleEvents: "true", orderBy: "startTime", maxResults: "2500",
    });
    const res = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${calendarId}/events?${params.toString()}`, {
      headers: { Authorization: "Bearer " + accessToken },
    });
    const json = await res.json();
    if (!res.ok) {
      throw new Error("Google Calendar API: " + (json.error?.message || res.status));
    }

    const items = Array.isArray(json.items) ? json.items : [];
    const blocks = items
      .filter((ev: any) => ev.status !== "cancelled" && ev.start && ev.end && (ev.start.dateTime || ev.start.date))
      .map((ev: any) => ({
        start: ev.start.dateTime ? new Date(ev.start.dateTime).toISOString() : new Date(ev.start.date + "T00:00:00Z").toISOString(),
        end: ev.end.dateTime ? new Date(ev.end.dateTime).toISOString() : new Date(ev.end.date + "T00:00:00Z").toISOString(),
        title: ev.summary || "",
      }));

    await supabase.from("immonova_calendar_busy_blocks")
      .delete().eq("user_id", conn.user_id).eq("provider", "google").gte("start_at", timeMin);

    if (blocks.length) {
      const rows = blocks.map((b: any) => ({
        start_at: b.start, end_at: b.end, title: b.title || null,
        source: "google", provider: "google", user_id: conn.user_id,
      }));
      const { error: insertError } = await supabase.from("immonova_calendar_busy_blocks").insert(rows);
      if (insertError) throw new Error("Blocchi letti ma non salvati: " + insertError.message);
    }

    await supabase.from("immonova_calendar_connections").update({
      last_synced_at: new Date().toISOString(),
      last_sync_error: null,
    }).eq("id", conn.id);

    return { user_id: conn.user_id, success: true, busy_blocks_synced: blocks.length };
  } catch (e) {
    const message = (e as Error)?.message || String(e);
    await supabase.from("immonova_calendar_connections").update({
      last_synced_at: new Date().toISOString(),
      last_sync_error: message,
    }).eq("id", conn.id);
    return { user_id: conn.user_id, success: false, error: message };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_e) { /* body vuoto è normale (chiamata da cron) */ }
  const onlyUserId = body && typeof body.user_id === "string" ? body.user_id : null;

  let query = supabase.from("immonova_calendar_connections")
    .select("id,user_id,google_calendar_id,google_access_token,google_refresh_token,google_token_expires_at")
    .eq("provider", "google").eq("active", true);
  if (onlyUserId) query = query.eq("user_id", onlyUserId);

  const { data: connections, error: connErr } = await query;
  if (connErr) {
    return jsonResponse({ success: false, error: "Errore lettura connessioni Google: " + connErr.message }, 500);
  }
  if (!connections || !connections.length) {
    return jsonResponse({ success: true, note: "Nessuna connessione Google Calendar attiva da sincronizzare.", results: [] }, 200);
  }

  const now = new Date();
  const timeMin = now.toISOString();
  const timeMax = new Date(now.getTime() + SYNC_DAYS_AHEAD * 86400000).toISOString();

  const results = [];
  for (const conn of connections) {
    results.push(await syncOneConnection(supabase, conn, timeMin, timeMax));
  }

  const anyFailed = results.some((r) => !r.success);
  return jsonResponse({ success: !anyFailed, results }, 200);
});
