// Supabase Edge Function: immonova-google-oauth-callback
// Google reindirizza QUI dopo il consenso dell'utente, con ?code=...&state=...
// Scambia il code per access_token+refresh_token e salva la connessione, poi
// reindirizza l'utente alla pagina del calendario con un esito in query string
// (così la pagina può mostrare un messaggio senza bisogno di API aggiuntive).
//
// Secret richiesti: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_OAUTH_REDIRECT_URI
// (deve combaciare ESATTAMENTE con quello configurato nel progetto Google Cloud e con
// quello usato da immonova-google-oauth-start), più SITE_URL (es.
// https://dominus-suite.it) per costruire il redirect finale verso il sito.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID");
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET");
const GOOGLE_OAUTH_REDIRECT_URI = Deno.env.get("GOOGLE_OAUTH_REDIRECT_URI");
const STATE_SECRET = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SITE_URL = Deno.env.get("SITE_URL") || "https://dominus-suite.it";

async function verifyState(state: string): Promise<string | null> {
  const parts = state.split(".");
  if (parts.length !== 2) return null;
  const [userId, sig] = parts;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(STATE_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(userId));
  const expectedSig = btoa(String.fromCharCode(...new Uint8Array(sigBuf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return sig === expectedSig ? userId : null;
}

function redirectToCalendar(status: string, message?: string): Response {
  const url = SITE_URL.replace(/\/$/, "") + "/admin/calendar.html?google_connect=" + encodeURIComponent(status) +
    (message ? "&google_connect_msg=" + encodeURIComponent(message) : "");
  return new Response(null, { status: 302, headers: { Location: url } });
}

serve(async (req) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const oauthError = url.searchParams.get("error");

  if (oauthError) {
    return redirectToCalendar("error", "Google ha rifiutato l'autorizzazione: " + oauthError);
  }
  if (!code || !state) {
    return redirectToCalendar("error", "Parametri mancanti nella risposta di Google.");
  }
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_OAUTH_REDIRECT_URI) {
    return redirectToCalendar("error", "Configurazione Google OAuth incompleta lato server.");
  }

  const userId = await verifyState(state);
  if (!userId) {
    return redirectToCalendar("error", "State non valido, riprova a collegare Google Calendar.");
  }

  try {
    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: GOOGLE_CLIENT_ID,
        client_secret: GOOGLE_CLIENT_SECRET,
        redirect_uri: GOOGLE_OAUTH_REDIRECT_URI,
        grant_type: "authorization_code",
      }),
    });
    const tokenJson = await tokenRes.json();
    if (!tokenRes.ok) {
      return redirectToCalendar("error", "Scambio token Google fallito: " + (tokenJson.error_description || tokenJson.error || tokenRes.status));
    }
    if (!tokenJson.refresh_token) {
      // Capita se l'utente aveva già autorizzato l'app senza revocare l'accesso: Google non
      // riemette un refresh_token. prompt=consent in oauth-start dovrebbe evitarlo, ma en caso
      // avvisiamo chiaramente invece di salvare una connessione che smetterà di funzionare al
      // primo refresh necessario.
      return redirectToCalendar("error", "Google non ha restituito un refresh token: revoca l'accesso DOMINUS dal tuo account Google e riprova.");
    }

    const expiresAt = new Date(Date.now() + (tokenJson.expires_in || 3600) * 1000).toISOString();

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { error: upsertError } = await supabase.from("immonova_calendar_connections").upsert({
      user_id: userId,
      provider: "google",
      active: true,
      google_access_token: tokenJson.access_token,
      google_refresh_token: tokenJson.refresh_token,
      google_token_expires_at: expiresAt,
      last_sync_error: null,
    }, { onConflict: "user_id,provider" });

    if (upsertError) {
      return redirectToCalendar("error", "Token ottenuti ma non salvati: " + upsertError.message);
    }

    return redirectToCalendar("success");
  } catch (e) {
    return redirectToCalendar("error", (e as Error)?.message || String(e));
  }
});
