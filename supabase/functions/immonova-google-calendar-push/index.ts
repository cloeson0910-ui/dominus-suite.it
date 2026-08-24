// Supabase Edge Function: immonova-google-calendar-push
// Equivalente di icloud-calendar-push ma per Google Calendar: scrive/aggiorna/elimina
// l'appuntamento DOMINUS nel Google Calendar personale del proprietario dell'evento
// (se lo ha collegato). Stesso comportamento "silenzioso" se non collegato: success con
// skipped=true, l'evento resta comunque salvato solo su DOMINUS.
//
// Input atteso (JSON): { action, event_id, title, event_type, start_at, end_at, notes,
//                         address, google_event_id (solo per update/delete) }

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

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function eventTypeLabel(type: string): string {
  const map: Record<string, string> = { telefonata: "Telefonata", riunione: "Riunione", visita_posto: "Visita sul posto" };
  return map[type] || type;
}

async function ensureFreshAccessToken(supabase: any, conn: any): Promise<string> {
  const expiresAt = conn.google_token_expires_at ? new Date(conn.google_token_expires_at).getTime() : 0;
  if (expiresAt - Date.now() > 60000 && conn.google_access_token) return conn.google_access_token;

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) throw new Error("GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET non configurati.");
  if (!conn.google_refresh_token) throw new Error("Nessun refresh_token salvato: l'utente deve ricollegare Google Calendar.");

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID, client_secret: GOOGLE_CLIENT_SECRET,
      refresh_token: conn.google_refresh_token, grant_type: "refresh_token",
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error("Rinnovo token Google fallito: " + (json.error_description || json.error || res.status));

  const newExpiresAt = new Date(Date.now() + (json.expires_in || 3600) * 1000).toISOString();
  await supabase.from("immonova_calendar_connections").update({
    google_access_token: json.access_token, google_token_expires_at: newExpiresAt,
  }).eq("id", conn.id);
  return json.access_token;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ success: false, error: "Metodo non consentito, usare POST." }, 405);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch (_e) { return jsonResponse({ success: false, error: "Corpo della richiesta non è JSON valido." }, 400); }

  const action = String(body.action || "create");
  const eventId = body.event_id;
  if (!eventId) return jsonResponse({ success: false, error: "Campo event_id obbligatorio." }, 400);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: eventRow, error: eventErr } = await supabase
    .from("immonova_calendar_events").select("created_by").eq("id", eventId).single();
  if (eventErr || !eventRow) {
    return jsonResponse({ success: false, error: "Evento non trovato (id " + eventId + ")." }, 404);
  }
  const ownerId = eventRow.created_by;

  const { data: conn } = await supabase
    .from("immonova_calendar_connections")
    .select("id,google_calendar_id,google_access_token,google_refresh_token,google_token_expires_at")
    .eq("user_id", ownerId).eq("provider", "google").eq("active", true).maybeSingle();

  const googleEventId = String(body.google_event_id || "");

  if (action === "delete") {
    // NOTA: come icloud-calendar-push, questa funzione NON cancella la riga in
    // immonova_calendar_events — lo fa il frontend dopo aver chiamato la pulizia esterna
    // su tutti i provider collegati, per evitare doppie cancellazioni/errori "not found".
    try {
      if (googleEventId && conn) {
        const accessToken = await ensureFreshAccessToken(supabase, conn);
        const calendarId = encodeURIComponent(conn.google_calendar_id || "primary");
        const delRes = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${calendarId}/events/${googleEventId}`, {
          method: "DELETE", headers: { Authorization: "Bearer " + accessToken },
        });
        if (!delRes.ok && delRes.status !== 404 && delRes.status !== 410) {
          const errText = await delRes.text();
          return jsonResponse({ success: false, error: "Google ha rifiutato l'eliminazione (HTTP " + delRes.status + "): " + errText.slice(0, 300) }, 502);
        }
      }
      return jsonResponse({ success: true }, 200);
    } catch (e) {
      return jsonResponse({ success: false, error: (e as Error)?.message || String(e) }, 500);
    }
  }

  if (!conn) {
    return jsonResponse({ success: true, skipped: true, note: "Nessuna connessione Google Calendar attiva per il proprietario dell'evento." }, 200);
  }

  const title = String(body.title || "Appuntamento DOMINUS");
  const eventType = String(body.event_type || "");
  const startAt = String(body.start_at || "");
  const endAt = String(body.end_at || "");
  const notes = String(body.notes || "");
  const address = String(body.address || "");
  if (!startAt || !endAt) return jsonResponse({ success: false, error: "Campi start_at, end_at obbligatori." }, 400);

  const payload = {
    summary: eventTypeLabel(eventType) + " — " + title,
    description: notes || undefined,
    location: address || undefined,
    start: { dateTime: startAt },
    end: { dateTime: endAt },
  };

  try {
    const accessToken = await ensureFreshAccessToken(supabase, conn);
    const calendarId = encodeURIComponent(conn.google_calendar_id || "primary");

    if (action === "update" && googleEventId) {
      const putRes = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${calendarId}/events/${googleEventId}`, {
        method: "PUT",
        headers: { Authorization: "Bearer " + accessToken, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const json = await putRes.json();
      if (!putRes.ok) {
        await supabase.from("immonova_calendar_events").update({ synced_to_google: false, google_sync_error: json.error?.message || String(putRes.status) }).eq("id", eventId);
        return jsonResponse({ success: false, error: "Google ha rifiutato l'aggiornamento: " + (json.error?.message || putRes.status) }, 502);
      }
      await supabase.from("immonova_calendar_events").update({ synced_to_google: true, google_sync_error: null }).eq("id", eventId);
      return jsonResponse({ success: true }, 200);
    }

    const postRes = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${calendarId}/events`, {
      method: "POST",
      headers: { Authorization: "Bearer " + accessToken, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const json = await postRes.json();
    if (!postRes.ok) {
      await supabase.from("immonova_calendar_events").update({ synced_to_google: false, google_sync_error: json.error?.message || String(postRes.status) }).eq("id", eventId);
      return jsonResponse({ success: false, error: "Google ha rifiutato la creazione: " + (json.error?.message || postRes.status) }, 502);
    }
    await supabase.from("immonova_calendar_events").update({ synced_to_google: true, google_event_id: json.id, google_sync_error: null }).eq("id", eventId);
    return jsonResponse({ success: true, google_event_id: json.id }, 200);
  } catch (e) {
    const message = (e as Error)?.message || String(e);
    await supabase.from("immonova_calendar_events").update({ synced_to_google: false, google_sync_error: message }).eq("id", eventId);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
