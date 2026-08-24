// Supabase Edge Function: immonova-calendar-connect-icloud
// Un utente autenticato collega il proprio account iCloud al calendario DOMINUS:
// riceve email + app-specific password, VERIFICA che funzionino davvero facendo una
// chiamata CalDAV di prova (altrimenti si scoprirebbe solo al primo sync automatico,
// magari ore dopo), e solo se valide le salva in immonova_calendar_connections.
//
// Input atteso (JSON):
// { icloud_username: string, icloud_app_password: string }
//
// Nota: la funzione richiede l'header Authorization dell'utente loggato (non usa
// service_role per l'identità del chiamante) così da poter scrivere la connessione
// per il SUO user_id senza doverlo fidare dal body.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CALDAV_BASE = "https://caldav.icloud.com";

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function verifyIcloudCredentials(username: string, appPassword: string): Promise<{ ok: boolean; error?: string }> {
  const authHeader = "Basic " + btoa(username + ":" + appPassword);
  const body = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop><D:current-user-principal/></D:prop>
</D:propfind>`;
  try {
    const res = await fetch(CALDAV_BASE + "/", {
      method: "PROPFIND",
      headers: { "Authorization": authHeader, "Content-Type": "application/xml; charset=utf-8", "Depth": "0" },
      body,
    });
    if (res.status === 401 || res.status === 403) {
      return { ok: false, error: "Credenziali iCloud rifiutate (email o password per app errata)." };
    }
    if (!res.ok) {
      return { ok: false, error: "iCloud ha risposto con errore HTTP " + res.status + "." };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: "Impossibile contattare iCloud: " + ((e as Error)?.message || String(e)) };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo non consentito, usare POST." }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ success: false, error: "Utente non autenticato." }, 401);
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData || !userData.user) {
    return jsonResponse({ success: false, error: "Sessione non valida." }, 401);
  }
  const userId = userData.user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ success: false, error: "Corpo della richiesta non è JSON valido." }, 400);
  }

  const icloudUsername = String(body.icloud_username || "").trim();
  const icloudAppPassword = String(body.icloud_app_password || "").trim();

  if (!icloudUsername || !icloudAppPassword) {
    return jsonResponse({ success: false, error: "Email iCloud e password per app sono entrambe obbligatorie." }, 400);
  }

  const verify = await verifyIcloudCredentials(icloudUsername, icloudAppPassword);
  if (!verify.ok) {
    return jsonResponse({ success: false, error: verify.error }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { error: upsertError } = await supabase.from("immonova_calendar_connections").upsert({
    user_id: userId,
    provider: "icloud",
    active: true,
    icloud_username: icloudUsername,
    icloud_app_password: icloudAppPassword,
    last_sync_error: null,
  }, { onConflict: "user_id,provider" });

  if (upsertError) {
    return jsonResponse({ success: false, error: "Credenziali verificate ma non salvate: " + upsertError.message }, 500);
  }

  return jsonResponse({ success: true }, 200);
});
