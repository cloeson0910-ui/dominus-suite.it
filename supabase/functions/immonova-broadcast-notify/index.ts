// Supabase Edge Function: immonova-broadcast-notify
// Invia una notifica push (Web Push / VAPID) a TUTTI gli utenti che hanno installato
// l'app / attivato le notifiche (tabella immonova_push_subscriptions, quella anonima
// usata da notifications-consent.html — nessun user_id, un solo grande pubblico).
// Pensata per comunicazioni libere dell'amministratore: un evento, un augurio, un saluto.
//
// Autenticazione: la richiesta deve arrivare con l'Authorization header dell'utente
// loggato (sessione admin/collaboratore). La funzione verifica che il chiamante abbia
// profiles.role = 'admin' prima di inviare qualsiasi cosa — evita che chiunque abbia
// un token valido possa spammare l'intera base di sottoscrittori.
//
// Input atteso (JSON):
// {
//   title: string,   // titolo notifica
//   body: string,    // testo notifica
//   url: string       // url da aprire al click (opzionale, default /index.html)
// }
//
// LEZIONE CRITICA del progetto: su risposta non-2xx, supabase-js client non popola
// result.data (resta null) e result.error.message è generico — il messaggio vero va
// letto da result.error.context. Per questo qui si restituisce sempre un body JSON
// leggibile { success, error } sia su successo che su errore.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "https://esm.sh/web-push@3.6.7";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY");
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY");
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:amministrazione@dominus-suite.it";

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo non consentito, usare POST." }, 405);
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
    return jsonResponse({ success: false, error: "Variabili SUPABASE_URL/SERVICE_ROLE_KEY/ANON_KEY non configurate." }, 500);
  }
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return jsonResponse({ success: false, error: "VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY non configurati tra i secret della edge function." }, 500);
  }

  // --- Verifica identità del chiamante e ruolo admin ---
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return jsonResponse({ success: false, error: "Autenticazione mancante." }, 401);
  }

  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: "Bearer " + token } },
  });
  const { data: userData, error: userErr } = await callerClient.auth.getUser();
  if (userErr || !userData || !userData.user) {
    return jsonResponse({ success: false, error: "Sessione non valida o scaduta." }, 401);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: callerProfile, error: profileErr } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", userData.user.id)
    .single();

  if (profileErr || !callerProfile || callerProfile.role !== "admin") {
    return jsonResponse({ success: false, error: "Solo un amministratore può inviare notifiche broadcast." }, 403);
  }

  // --- Corpo della richiesta ---
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ success: false, error: "Corpo della richiesta non è JSON valido." }, 400);
  }

  // Modalità "solo conteggio": usata dalla pagina admin per mostrare quante persone
  // riceverebbero la notifica, PRIMA dell'invio vero e proprio. Serve perché
  // immonova_push_subscriptions non ha (volutamente, per privacy) una policy di SELECT
  // per nessuno, nemmeno per gli admin: il conteggio va quindi letto qui, lato server,
  // con la service_role key, dopo aver già verificato sopra che il chiamante è admin.
  if (body.count_only === true) {
    const { count, error: countErr } = await supabase
      .from("immonova_push_subscriptions")
      .select("id", { count: "exact", head: true });
    if (countErr) {
      return jsonResponse({ success: false, error: "Errore conteggio subscription: " + countErr.message }, 500);
    }
    return jsonResponse({ success: true, count: count || 0 }, 200);
  }

  const title = String(body.title || "DOMINUS").trim();
  const notifBody = String(body.body || "").trim();
  const url = String(body.url || "/index.html").trim();

  if (!notifBody) {
    return jsonResponse({ success: false, error: "Campo 'body' (testo notifica) mancante." }, 400);
  }

  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

  const { data: subs, error: subsErr } = await supabase
    .from("immonova_push_subscriptions")
    .select("id, endpoint, p256dh, auth");

  if (subsErr) {
    return jsonResponse({ success: false, error: "Errore lettura subscription: " + subsErr.message }, 500);
  }
  if (!subs || !subs.length) {
    return jsonResponse({ success: true, sent: 0, note: "Nessuna subscription push trovata (nessuno ha ancora attivato le notifiche)." }, 200);
  }

  const payload = JSON.stringify({ title, body: notifBody, url });

  let sent = 0;
  const failures: { endpoint: string; error: string }[] = [];
  const staleSubIds: string[] = [];

  for (const sub of subs) {
    try {
      await webpush.sendNotification(
        {
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        },
        payload,
      );
      sent++;
    } catch (e: any) {
      const statusCode = e && (e.statusCode || (e.body && e.body.statusCode));
      // 404/410 = subscription scaduta o revocata dal browser: la rimuoviamo per non
      // ritentare invii inutili su un endpoint che non esiste più.
      if (statusCode === 404 || statusCode === 410) {
        staleSubIds.push(sub.id);
      }
      failures.push({ endpoint: sub.endpoint, error: (e && e.message) || String(e) });
    }
  }

  if (staleSubIds.length) {
    await supabase.from("immonova_push_subscriptions").delete().in("id", staleSubIds);
  }

  return jsonResponse({
    success: true,
    sent,
    total: subs.length,
    failed: failures.length,
    failures: failures.length ? failures : undefined,
    removed_stale: staleSubIds.length || undefined,
  }, 200);
});
