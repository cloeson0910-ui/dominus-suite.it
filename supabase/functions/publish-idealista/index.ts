// publish-idealista
// SCHELETRO — da completare quando Idealista fornisce le credenziali/API
// per l'agenzia specifica. A differenza di Immobiliare.it, Idealista non
// offre un'API self-service pubblica: bisogna richiedere l'attivazione al
// loro supporto tecnico, che fornisce endpoint e metodo di autenticazione
// specifici per l'account.
//
// Questa function è già collegata alla pagina Impostazioni Portali e al
// checkbox "Pubblica su Idealista" in ogni opportunità — quando avrai le
// credenziali, basta completare la chiamata HTTP qui sotto (segnata con
// TODO) seguendo la documentazione che ti manderà Idealista, senza dover
// toccare nient'altro nel sito.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({}, 200);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return jsonResponse({ success: false, error: "Non autenticato" }, 401);

    const body = await req.json();
    const { opportunity_id, action } = body;
    if (!opportunity_id || !["publish", "remove"].includes(action)) {
      return jsonResponse({ success: false, error: "opportunity_id e action ('publish'|'remove') obbligatori" }, 400);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: settings } = await admin
      .from("immonova_portal_settings").select("enabled, credentials").eq("portal_key", "idealista").maybeSingle();

    if (!settings?.enabled) {
      return jsonResponse({ success: false, error: "Pubblicazione su Idealista non ancora attiva su questo sito" }, 400);
    }

    // ------------------------------------------------------------------
    // TODO: sostituire questo blocco con la chiamata reale una volta
    // ricevute le specifiche da Idealista (endpoint, formato payload,
    // metodo di autenticazione — spesso OAuth2 client-credentials).
    // Esempio indicativo (DA VERIFICARE con la loro documentazione):
    //
    //   const tokenRes = await fetch("https://api.idealista.com/oauth/token", {
    //     method: "POST",
    //     headers: { Authorization: "Basic " + btoa(`${apiKey}:${apiSecret}`) },
    //     body: "grant_type=client_credentials",
    //   });
    //   const { access_token } = await tokenRes.json();
    //   const publishRes = await fetch("https://api.idealista.com/3.5/ads", {
    //     method: "POST",
    //     headers: { Authorization: `Bearer ${access_token}`, "Content-Type": "application/json" },
    //     body: JSON.stringify({ /* mappatura campi opportunity -> formato Idealista */ }),
    //   });
    // ------------------------------------------------------------------

    await admin.from("immonova_portal_sync_log").insert({
      opportunity_id,
      portal_key: "idealista",
      status: "errore",
      message: "Integrazione Idealista non ancora configurata — contatta il supporto Idealista per ottenere le credenziali API, poi completa publish-idealista/index.ts",
    });

    return jsonResponse({
      success: false,
      error: "Integrazione Idealista non ancora configurata. Serve prima richiedere l'attivazione API al supporto Idealista.",
    }, 501);
  } catch (e) {
    return jsonResponse({ success: false, error: "Errore interno: " + String(e) }, 500);
  }
});
