// Supabase Edge Function: icloud-calendar-sync
// Legge da iCloud (via CalDAV) quali fasce orarie sono occupate nei prossimi 60 giorni,
// PER OGNI utente che ha collegato un account iCloud (tabella
// immonova_calendar_connections, provider='icloud'), non solo per l'admin come prima.
// Le fasce vengono salvate in immonova_calendar_busy_blocks con user_id + provider='icloud'.
// Da schedulare ogni 5-10 minuti via Supabase Cron (vedi setup-calendar-cron.sql).
//
// Le credenziali (email iCloud + app-specific password) NON sono più secret globali:
// ogni collaboratore le inserisce collegando il proprio account (vedi
// immonova-calendar-connect-icloud), salvate nella riga della sua connessione.

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
const SYNC_DAYS_AHEAD = 60;

function resolveUrl(href: string): string {
  if (/^https?:\/\//i.test(href)) return href;
  return CALDAV_BASE + href;
}

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
    headers: {
      "Authorization": authHeader,
      "Content-Type": "application/xml; charset=utf-8",
      ...extraHeaders,
    },
    body,
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

async function discoverPrincipal(authHeader: string): Promise<string> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop><D:current-user-principal/></D:prop>
</D:propfind>`;
  const res = await caldavRequest(CALDAV_BASE + "/", "PROPFIND", body, authHeader, { "Depth": "0" });
  if (!res.ok) throw new Error("Scoperta principal fallita (HTTP " + res.status + "): " + res.text.slice(0, 500));
  const match = res.text.match(/<[^>]*current-user-principal[^>]*>\s*<[^>]*href[^>]*>([^<]+)</i);
  if (!match) throw new Error("Principal non trovato nella risposta iCloud: " + res.text.slice(0, 500));
  return match[1];
}

async function discoverCalendarHome(principalPath: string, authHeader: string): Promise<string> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop><C:calendar-home-set/></D:prop>
</D:propfind>`;
  const res = await caldavRequest(resolveUrl(principalPath), "PROPFIND", body, authHeader, { "Depth": "0" });
  if (!res.ok) throw new Error("Scoperta calendar-home fallita (HTTP " + res.status + "): " + res.text.slice(0, 500));
  const match = res.text.match(/<[^>]*calendar-home-set[^>]*>\s*<[^>]*href[^>]*>([^<]+)</i);
  if (!match) throw new Error("Calendar-home non trovato nella risposta iCloud: " + res.text.slice(0, 500));
  return match[1];
}

async function listCalendars(calendarHomePath: string, authHeader: string): Promise<string[]> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:resourcetype/>
    <D:displayname/>
  </D:prop>
</D:propfind>`;
  const res = await caldavRequest(resolveUrl(calendarHomePath), "PROPFIND", body, authHeader, { "Depth": "1" });
  if (!res.ok) throw new Error("Elenco calendari fallito (HTTP " + res.status + "): " + res.text.slice(0, 500));

  const hrefs: string[] = [];
  const responseBlocks = res.text.split(/<[\w.-]*:?response(?:\s[^>]*)?>/i).slice(1);
  for (const block of responseBlocks) {
    const resourcetypeMatch = block.match(/<[\w.-]*:?resourcetype[^>]*>([\s\S]*?)<\/[\w.-]*:?resourcetype>/i);
    const isCalendar = !!(resourcetypeMatch && /<[\w.-]*:?calendar\b/i.test(resourcetypeMatch[1]));
    const hrefMatch = block.match(/<[\w.-]*:?href[^>]*>([^<]+)</i);
    if (isCalendar && hrefMatch && hrefMatch[1] !== calendarHomePath) {
      hrefs.push(hrefMatch[1]);
    }
  }
  return hrefs;
}

async function fetchBusyBlocks(calendarPath: string, rangeStart: string, rangeEnd: string, authHeader: string): Promise<{ start: string; end: string; title: string }[]> {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop><C:calendar-data/></D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT">
        <C:time-range start="${rangeStart}" end="${rangeEnd}"/>
      </C:comp-filter>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>`;
  const res = await caldavRequest(resolveUrl(calendarPath), "REPORT", body, authHeader, { "Depth": "1" });
  if (!res.ok) return [];

  const blocks: { start: string; end: string; title: string }[] = [];
  const icsBlocks = res.text.match(/BEGIN:VEVENT[\s\S]*?END:VEVENT/g) || [];
  for (const ics of icsBlocks) {
    const dtStart = ics.match(/DTSTART[^:]*:([0-9TZ]+)/);
    const dtEnd = ics.match(/DTEND[^:]*:([0-9TZ]+)/);
    if (dtStart && dtEnd) {
      blocks.push({ start: parseIcsDate(dtStart[1]), end: parseIcsDate(dtEnd[1]), title: parseIcsSummary(ics) });
    }
  }
  return blocks;
}

function unfoldIcs(text: string): string {
  return text.replace(/\r?\n[ \t]/g, "");
}
function decodeIcsText(value: string): string {
  return value
    .replace(/\\n/gi, " ")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\")
    .trim();
}
function parseIcsSummary(icsBlock: string): string {
  const unfolded = unfoldIcs(icsBlock);
  const match = unfolded.match(/^SUMMARY(?:;[^:\n]*)?:(.*)$/mi);
  if (!match) return "";
  return decodeIcsText(match[1]);
}

function lastSundayOfMonth(year: number, month: number): number {
  const d = new Date(Date.UTC(year, month, 0));
  return d.getUTCDate() - d.getUTCDay();
}
function italyOffsetMinutes(year: number, month: number, day: number): number {
  const marchLastSunday = lastSundayOfMonth(year, 3);
  const octLastSunday = lastSundayOfMonth(year, 10);
  const isDST = (month > 3 && month < 10) ||
    (month === 3 && day >= marchLastSunday) ||
    (month === 10 && day < octLastSunday);
  return isDST ? 120 : 60;
}
function parseIcsDate(raw: string): string {
  const y = Number(raw.slice(0, 4)), mo = Number(raw.slice(4, 6)), d = Number(raw.slice(6, 8));
  const h = Number(raw.slice(9, 11) || "0"), mi = Number(raw.slice(11, 13) || "0"), s = Number(raw.slice(13, 15) || "0");

  if (raw.endsWith("Z")) {
    return new Date(Date.UTC(y, mo - 1, d, h, mi, s)).toISOString();
  }

  const offsetMin = italyOffsetMinutes(y, mo, d);
  const utcMillis = Date.UTC(y, mo - 1, d, h, mi, s) - offsetMin * 60000;
  return new Date(utcMillis).toISOString();
}

function icsDateFormat(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

// Sincronizza UN utente/connessione. Non lancia mai fuori dal chiamante: ritorna sempre
// un risultato, così un fallimento su un collaboratore non blocca la sync degli altri.
async function syncOneConnection(supabase: any, conn: any, rangeStart: string, rangeEnd: string, now: Date) {
  const authHeader = basicAuthHeader(conn.icloud_username, conn.icloud_app_password);
  try {
    const principalPath = await discoverPrincipal(authHeader);
    const calendarHomePath = await discoverCalendarHome(principalPath, authHeader);
    const calendarPaths = await listCalendars(calendarHomePath, authHeader);

    let allBlocks: { start: string; end: string; title: string }[] = [];
    for (const calPath of calendarPaths) {
      const blocks = await fetchBusyBlocks(calPath, rangeStart, rangeEnd, authHeader);
      allBlocks = allBlocks.concat(blocks);
    }

    // Sostituisce l'intera cache futura DI QUESTO utente (mai quella degli altri).
    await supabase.from("immonova_calendar_busy_blocks")
      .delete().eq("user_id", conn.user_id).eq("provider", "icloud").gte("start_at", now.toISOString());

    if (allBlocks.length) {
      const rows = allBlocks.map((b) => ({
        start_at: b.start, end_at: b.end, title: b.title || null,
        source: "icloud", provider: "icloud", user_id: conn.user_id,
      }));
      const { error: insertError } = await supabase.from("immonova_calendar_busy_blocks").insert(rows);
      if (insertError) throw new Error("Blocchi letti ma non salvati: " + insertError.message);
    }

    await supabase.from("immonova_calendar_connections").update({
      last_synced_at: new Date().toISOString(),
      last_sync_error: null,
    }).eq("id", conn.id);

    return { user_id: conn.user_id, success: true, busy_blocks_synced: allBlocks.length };
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
    .select("id,user_id,icloud_username,icloud_app_password")
    .eq("provider", "icloud").eq("active", true);
  if (onlyUserId) query = query.eq("user_id", onlyUserId);

  const { data: connections, error: connErr } = await query;
  if (connErr) {
    return jsonResponse({ success: false, error: "Errore lettura connessioni iCloud: " + connErr.message }, 500);
  }
  if (!connections || !connections.length) {
    return jsonResponse({ success: true, note: "Nessuna connessione iCloud attiva da sincronizzare.", results: [] }, 200);
  }

  const now = new Date();
  const rangeEndDate = new Date(now.getTime() + SYNC_DAYS_AHEAD * 86400000);
  const rangeStart = icsDateFormat(now);
  const rangeEnd = icsDateFormat(rangeEndDate);

  const results = [];
  for (const conn of connections) {
    results.push(await syncOneConnection(supabase, conn, rangeStart, rangeEnd, now));
  }

  const anyFailed = results.some((r) => !r.success);
  return jsonResponse({ success: !anyFailed, results }, 200);
});
