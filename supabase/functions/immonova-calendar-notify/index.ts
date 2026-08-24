// Supabase Edge Function: immonova-calendar-notify
// Invia una notifica push (Web Push / VAPID, stesso schema già usato per gli avvisi
// preferiti) a uno o più collaboratori autenticati, quando un evento del calendario
// li coinvolge (invitati come partecipanti, o un partecipante rimosso).
//
// Input atteso (JSON):
// {
//   user_ids: string[],        // id (profiles.id) dei destinatari
//   title: string,             // titolo notifica
//   body: string,              // testo notifica
//   url: string                // url da aprire al click (opzionale, default /admin/calendar.html)
// }
//
// LEZIONE CRITICA del progetto (vedi memoria): quando questa funzione risponde con status
// non-2xx, supabase-js sul client NON mette il body JSON in result.data — resta null — e
// result.error.message è sempre il testo fisso generico. Il messaggio vero va letto da
// result.error.context. Per questo qui restituiamo SEMPRE un body JSON leggibile
// { success, error } sia su successo che su errore.

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
// NOTA: nome del secret da confermare — se nel progetto è già configurato con un nome
// diverso da questi due, va aggiornato qui (e nella variabile corrispondente più sotto).
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
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return jsonResponse({ success: false, error: "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY non configurati." }, 500);
  }
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return jsonResponse({ success: false, error: "VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY non configurati tra i secret della edge function." }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ success: false, error: "Corpo della richiesta non è JSON valido." }, 400);
  }

  const userIds = Array.isArray(body.user_ids) ? body.user_ids.map((v) => String(v)).filter(Boolean) : [];
  const title = String(body.title || "DOMINUS Calendario").trim();
  const notifBody = String(body.body || "").trim();
  const url = String(body.url || "/admin/calendar.html").trim();

  if (!userIds.length) {
    return jsonResponse({ success: false, error: "Campo 'user_ids' mancante o vuoto." }, 400);
  }
  if (!notifBody) {
    return jsonResponse({ success: false, error: "Campo 'body' (testo notifica) mancante." }, 400);
  }

  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: subs, error: subsErr } = await supabase
    .from("immonova_calendar_push_subscriptions")
    .select("id, user_id, endpoint, p256dh, auth")
    .in("user_id", userIds);

  if (subsErr) {
    return jsonResponse({ success: false, error: "Errore lettura subscription: " + subsErr.message }, 500);
  }
  if (!subs || !subs.length) {
    // Non è un errore: l'utente potrebbe non aver mai attivato le notifiche push.
    return jsonResponse({ success: true, sent: 0, note: "Nessuna subscription push trovata per i destinatari indicati." }, 200);
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
    await supabase.from("immonova_calendar_push_subscriptions").delete().in("id", staleSubIds);
  }

  return jsonResponse({
    success: true,
    sent,
    failed: failures.length,
    failures: failures.length ? failures : undefined,
    removed_stale: staleSubIds.length || undefined,
  }, 200);
});
