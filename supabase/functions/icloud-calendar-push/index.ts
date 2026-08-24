// Supabase Edge Function: icloud-calendar-push
// Quando un utente fissa un appuntamento da DOMINUS, questa funzione lo scrive anche sul
// SUO calendario iCloud personale (se lo ha collegato) — comparirà su iPhone/Mac.
// Chiamata da calendar.html subito dopo aver salvato la riga in immonova_calendar_events.
//
// Input atteso (JSON): { event_id, title, event_type, start_at, end_at, notes, address }
//
// A differenza della versione precedente (solo per Claudio, credenziali da secret
// globali), qui le credenziali vengono lette dalla connessione iCloud del PROPRIETARIO
// dell'evento (immonova_calendar_connections, letto tramite created_by dell'evento). Se
// quell'utente non ha collegato un account iCloud, la funzione non è un errore: risponde
// success con skipped=true, così l'evento resta comunque salvato solo su DOMINUS.
//
// Secret opzionale: ICLOUD_CALENDAR_NAME — nome esatto (displayname) del calendario iCloud
// su cui scrivere i nuovi appuntamenti, se si vuole evitare "il primo trovato".

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CALDAV_BASE = "https://caldav.icloud.com";

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function basicAuthHeader(username: string, appPassword: string): string {
  return "Basic " + btoa(username + ":" + appPassword);
}

async function caldavRequest(url: string, method: string, body: string, authHeader: string, extraHeaders: Record<string, string> = {}) {
  const res = await fetch(url, {
    method,
    headers: { "Authorization": authHeader, ...extraHeaders },
    body,
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

function resolveUrl(href: string): string {
  if (/^https?:\/\//i.test(href)) return href;
  return CALDAV_BASE + href;
}

async function discoverPrincipal(authHeader: string): Promise<string> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop><D:current-user-principal/></D:prop>
</D:propfind>`;
  const res = await caldavRequest(CALDAV_BASE + "/", "PROPFIND", body, authHeader, { "Depth": "0", "Content-Type": "application/xml; charset=utf-8" });
  if (!res.ok) throw new Error("Scoperta principal fallita (HTTP " + res.status + "): " + res.text.slice(0, 500));
  const match = res.text.match(/<[^>]*current-user-principal[^>]*>\s*<[^>]*href[^>]*>([^<]+)</i);
  if (!match) throw new Error("Principal non trovato: " + res.text.slice(0, 500));
  return match[1];
}

async function discoverCalendarHome(principalPath: string, authHeader: string): Promise<string> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop><C:calendar-home-set/></D:prop>
</D:propfind>`;
  const res = await caldavRequest(resolveUrl(principalPath), "PROPFIND", body, authHeader, { "Depth": "0", "Content-Type": "application/xml; charset=utf-8" });
  if (!res.ok) throw new Error("Scoperta calendar-home fallita (HTTP " + res.status + "): " + res.text.slice(0, 500));
  const match = res.text.match(/<[^>]*calendar-home-set[^>]*>\s*<[^>]*href[^>]*>([^<]+)</i);
  if (!match) throw new Error("Calendar-home non trovato: " + res.text.slice(0, 500));
  return match[1];
}

async function findFirstWritableCalendar(calendarHomePath: string, authHeader: string): Promise<string> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:resourcetype/>
    <D:displayname/>
  </D:prop>
</D:propfind>`;
  const res = await caldavRequest(resolveUrl(calendarHomePath), "PROPFIND", body, authHeader, { "Depth": "1", "Content-Type": "application/xml; charset=utf-8" });
  if (!res.ok) throw new Error("Elenco calendari fallito (HTTP " + res.status + "): " + res.text.slice(0, 500));

  const targetName = (Deno.env.get("ICLOUD_CALENDAR_NAME") || "").trim().toLowerCase();

  const responseBlocks = res.text.split(/<[\w.-]*:?response(?:\s[^>]*)?>/i).slice(1);
  const found: { href: string; name: string }[] = [];

  for (const block of responseBlocks) {
    const resourcetypeMatch = block.match(/<[\w.-]*:?resourcetype[^>]*>([\s\S]*?)<\/[\w.-]*:?resourcetype>/i);
    const isCalendar = !!(resourcetypeMatch && /<[\w.-]*:?calendar\b/i.test(resourcetypeMatch[1]));
    const hrefMatch = block.match(/<[\w.-]*:?href[^>]*>([^<]+)</i);
    const nameMatch = block.match(/<[\w.-]*:?displayname[^>]*>([^<]*)<\/[\w.-]*:?displayname>/i);
    if (isCalendar && hrefMatch && hrefMatch[1] !== calendarHomePath) {
      found.push({ href: hrefMatch[1], name: (nameMatch ? nameMatch[1] : "").trim() });
    }
  }

  if (!found.length) {
    throw new Error("Nessun calendario scrivibile trovato su iCloud. Anteprima risposta ricevuta: " + res.text.slice(0, 800));
  }

  if (targetName) {
    const match = found.find((c) => c.name.toLowerCase() === targetName);
    if (match) return match.href;
    throw new Error(
      "Nessun calendario chiamato \"" + Deno.env.get("ICLOUD_CALENDAR_NAME") + "\" trovato su iCloud. " +
      "Calendari trovati: " + found.map((c) => "\"" + c.name + "\"").join(", ")
    );
  }

  return found[0].href;
}

function icsDateFormat(iso: string): string {
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

function escapeIcsText(value: string): string {
  return String(value || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
}

function eventTypeLabel(type: string): string {
  const map: Record<string, string> = {
    telefonata: "Telefonata",
    riunione: "Riunione",
    visita_posto: "Visita sul posto",
  };
  return map[type] || type;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo non consentito, usare POST." }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ success: false, error: "Corpo della richiesta non è JSON valido." }, 400);
  }

  const action = String(body.action || "create");
  const eventId = body.event_id;

  if (!eventId) {
    return jsonResponse({ success: false, error: "Campo event_id obbligatorio." }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Il proprietario dell'evento determina DI CHI è la connessione iCloud da usare.
  // Sul delete l'evento esiste ancora in DB (viene rimosso solo dopo, qui sotto).
  const { data: eventRow, error: eventErr } = await supabase
    .from("immonova_calendar_events").select("created_by").eq("id", eventId).single();
  if (eventErr || !eventRow) {
    return jsonResponse({ success: false, error: "Evento non trovato (id " + eventId + ")." }, 404);
  }
  const ownerId = eventRow.created_by;

  const { data: conn } = await supabase
    .from("immonova_calendar_connections")
    .select("icloud_username,icloud_app_password")
    .eq("user_id", ownerId).eq("provider", "icloud").eq("active", true).maybeSingle();

  if (action === "delete") {
    // NOTA: questa funzione NON cancella più la riga in immonova_calendar_events — se
    // esistono più connessioni (iCloud + Google) sullo stesso evento, la cancellazione
    // andrebbe duplicata/fallirebbe alla seconda chiamata. La riga viene cancellata dal
    // frontend DOPO aver chiamato la pulizia esterna su tutti i provider collegati.
    const icloudHref = String(body.icloud_href || "");
    try {
      if (icloudHref && conn) {
        const authHeader = basicAuthHeader(conn.icloud_username, conn.icloud_app_password);
        const delRes = await caldavRequest(resolveUrl(icloudHref), "DELETE", "", authHeader, {});
        if (!delRes.ok && delRes.status !== 404) {
          return jsonResponse({ success: false, error: "iCloud ha rifiutato l'eliminazione (HTTP " + delRes.status + "): " + delRes.text.slice(0, 300) }, 502);
        }
      }
      return jsonResponse({ success: true }, 200);
    } catch (e) {
      return jsonResponse({ success: false, error: (e as Error)?.message || String(e) }, 500);
    }
  }

  if (!conn) {
    // Non è un errore: l'utente semplicemente non ha collegato iCloud. L'evento resta
    // salvato solo su DOMINUS.
    return jsonResponse({ success: true, skipped: true, note: "Nessuna connessione iCloud attiva per il proprietario dell'evento." }, 200);
  }
  const authHeader = basicAuthHeader(conn.icloud_username, conn.icloud_app_password);

  const title = String(body.title || "Appuntamento DOMINUS");
  const eventType = String(body.event_type || "");
  const startAt = String(body.start_at || "");
  const endAt = String(body.end_at || "");
  const notes = String(body.notes || "");
  const address = String(body.address || "");

  if (!startAt || !endAt) {
    return jsonResponse({ success: false, error: "Campi start_at, end_at obbligatori." }, 400);
  }

  if (action === "update") {
    const icloudHref = String(body.icloud_href || "");
    const icloudUid = String(body.icloud_uid || "");

    if (!icloudHref || !icloudUid) {
      return await createIcloudEvent(supabase, authHeader, String(eventId), title, eventType, startAt, endAt, notes, address);
    }

    try {
      const fullTitle = eventTypeLabel(eventType) + " — " + title;
      const ics = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//DOMINUS//Calendario//IT",
        "BEGIN:VEVENT",
        "UID:" + icloudUid,
        "DTSTAMP:" + icsDateFormat(new Date().toISOString()),
        "DTSTART:" + icsDateFormat(startAt),
        "DTEND:" + icsDateFormat(endAt),
        "SUMMARY:" + escapeIcsText(fullTitle),
        notes ? "DESCRIPTION:" + escapeIcsText(notes) : "",
        address ? "LOCATION:" + escapeIcsText(address) : "",
        "END:VEVENT",
        "END:VCALENDAR",
      ].filter(Boolean).join("\r\n");

      const putRes = await caldavRequest(resolveUrl(icloudHref), "PUT", ics, authHeader, {
        "Content-Type": "text/calendar; charset=utf-8",
      });

      if (!putRes.ok) {
        await supabase.from("immonova_calendar_events").update({
          synced_to_icloud: false,
          sync_error: "HTTP " + putRes.status + ": " + putRes.text.slice(0, 300),
        }).eq("id", eventId);
        return jsonResponse({ success: false, error: "iCloud ha rifiutato l'aggiornamento (HTTP " + putRes.status + "): " + putRes.text.slice(0, 300) }, 502);
      }

      await supabase.from("immonova_calendar_events").update({
        synced_to_icloud: true,
        sync_error: null,
      }).eq("id", eventId);

      return jsonResponse({ success: true }, 200);
    } catch (e) {
      const message = (e as Error)?.message || String(e);
      await supabase.from("immonova_calendar_events").update({ synced_to_icloud: false, sync_error: message }).eq("id", eventId);
      return jsonResponse({ success: false, error: message }, 500);
    }
  }

  return await createIcloudEvent(supabase, authHeader, String(eventId), title, eventType, startAt, endAt, notes, address);
});

async function createIcloudEvent(supabase: ReturnType<typeof createClient>, authHeader: string, eventId: string, title: string, eventType: string, startAt: string, endAt: string, notes: string, address: string) {
  try {
    const principalPath = await discoverPrincipal(authHeader);
    const calendarHomePath = await discoverCalendarHome(principalPath, authHeader);
    const calendarPath = await findFirstWritableCalendar(calendarHomePath, authHeader);

    const uid = "immonova-" + eventId + "-" + Date.now() + "@dominus-suite.it";
    const fullTitle = eventTypeLabel(eventType) + " — " + title;

    const ics = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//DOMINUS//Calendario//IT",
      "BEGIN:VEVENT",
      "UID:" + uid,
      "DTSTAMP:" + icsDateFormat(new Date().toISOString()),
      "DTSTART:" + icsDateFormat(startAt),
      "DTEND:" + icsDateFormat(endAt),
      "SUMMARY:" + escapeIcsText(fullTitle),
      notes ? "DESCRIPTION:" + escapeIcsText(notes) : "",
      address ? "LOCATION:" + escapeIcsText(address) : "",
      "END:VEVENT",
      "END:VCALENDAR",
    ].filter(Boolean).join("\r\n");

    const eventHref = calendarPath + uid + ".ics";
    const putRes = await caldavRequest(resolveUrl(eventHref), "PUT", ics, authHeader, {
      "Content-Type": "text/calendar; charset=utf-8",
    });

    if (!putRes.ok) {
      await supabase.from("immonova_calendar_events").update({
        synced_to_icloud: false,
        sync_error: "HTTP " + putRes.status + ": " + putRes.text.slice(0, 300),
      }).eq("id", eventId);
      return jsonResponse({ success: false, error: "iCloud ha rifiutato la scrittura (HTTP " + putRes.status + "): " + putRes.text.slice(0, 300) }, 502);
    }

    await supabase.from("immonova_calendar_events").update({
      synced_to_icloud: true,
      icloud_uid: uid,
      icloud_href: eventHref,
      sync_error: null,
    }).eq("id", eventId);

    return jsonResponse({ success: true }, 200);
  } catch (e) {
    const message = (e as Error)?.message || String(e);
    await supabase.from("immonova_calendar_events").update({
      synced_to_icloud: false,
      sync_error: message,
    }).eq("id", eventId);
    return jsonResponse({ success: false, error: message }, 500);
  }
}
