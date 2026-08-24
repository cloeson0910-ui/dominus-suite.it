// Supabase Edge Function: immonova-google-oauth-start
// Genera l'URL a cui reindirizzare l'utente per collegare il proprio Google Calendar
// (schermata di consenso Google). Il "state" contiene lo user_id firmato in modo
// semplice con lo stesso service_role secret, così immonova-google-oauth-callback può
// verificare che non sia stato manomesso senza dover mantenere una tabella di stati.
//
// Secret richiesti: GOOGLE_CLIENT_ID, GOOGLE_OAUTH_REDIRECT_URI (l'URL di QUESTA edge
// function immonova-google-oauth-callback, es.
// https://<project-ref>.supabase.co/functions/v1/immonova-google-oauth-callback)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID");
const GOOGLE_OAUTH_REDIRECT_URI = Deno.env.get("GOOGLE_OAUTH_REDIRECT_URI");
const STATE_SECRET = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; // riusato solo per firmare lo state, non per accedere al DB qui

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function signState(userId: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(STATE_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(userId));
  const sig = btoa(String.fromCharCode(...new Uint8Array(sigBuf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return userId + "." + sig;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (!GOOGLE_CLIENT_ID || !GOOGLE_OAUTH_REDIRECT_URI) {
    return jsonResponse({ success: false, error: "GOOGLE_CLIENT_ID o GOOGLE_OAUTH_REDIRECT_URI non configurati tra i secret." }, 500);
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

  const state = await signState(userData.user.id);

  const params = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    redirect_uri: GOOGLE_OAUTH_REDIRECT_URI,
    response_type: "code",
    scope: "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.readonly",
    access_type: "offline",
    prompt: "consent", // forza il rilascio di un refresh_token anche se l'utente aveva già autorizzato prima
    state,
  });

  const authUrl = "https://accounts.google.com/o/oauth2/v2/auth?" + params.toString();
  return jsonResponse({ success: true, auth_url: authUrl }, 200);
});
