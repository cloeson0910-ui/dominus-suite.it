// publish-immobiliare-it
// Pubblica (o rimuove) un'opportunità su Immobiliare.it via la loro API
// REST reale: PUT per inserire/aggiornare, DELETE per rimuovere. Le
// credenziali (username/password Basic Auth + X-IMMO-SOURCE, forniti dal
// supporto Immobiliare.it all'agenzia) sono lette da
// immonova_portal_settings, non hardcoded — ogni sito cliente usa le
// proprie.
//
// NOTA: Immobiliare.it richiede che l'agenzia comunichi PREVENTIVAMENTE gli
// IP pubblici del server da cui parte questa function (Project Settings ->
// Edge Functions non espone IP statici di default: se il supporto
// Immobiliare.it lo richiede, valutare un relay con IP fisso).
//
// Richiesta: { opportunity_id, action: "publish" | "remove" }

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

// Mappa il tipo immobile usato in Dominus sul codice numerico IDType
// richiesto dallo schema Immobiliare.it. Da completare/verificare con la
// tabella codici ufficiale fornita dal loro supporto tecnico — questi sono
// i valori più comuni per residenziale.
const ID_TYPE_MAP: Record<string, number> = {
  appartamento: 1,
  villa: 5,
  attico: 8,
  rustico: 13,
  terreno: 30,
};

function buildXmlPayload(opp: Record<string, unknown>, agencyEmail: string) {
  const idType = ID_TYPE_MAP[String(opp.property_type || "").toLowerCase()] || 1;
  const contractType = opp.listing_type === "affitto" ? "R" : "S";
  const lastUpdate = new Date().toISOString().slice(0, 19);

  const images = Array.isArray(opp.photos)
    ? (opp.photos as string[]).slice(0, 30).map((url) => `<Multimedia><Item Type="Picture" URL="${escapeXml(url)}"/></Multimedia>`).join("")
    : "";

  return `<?xml version="1.0" encoding="UTF-8"?>
<Ad>
  <UniqueID>${escapeXml(String(opp.id))}</UniqueID>
  <ContactEmail>${escapeXml(agencyEmail)}</ContactEmail>
  <LastUpdate>${lastUpdate}</LastUpdate>
  <IDType>${idType}</IDType>
  <ContractType>${contractType}</ContractType>
  <Title>${escapeXml(String(opp.title || ""))}</Title>
  <Description>${escapeXml(String(opp.description || ""))}</Description>
  <Price>${Number(opp.price || 0)}</Price>
  <Address>${escapeXml(String(opp.address || ""))}</Address>
  <City>${escapeXml(String(opp.city || ""))}</City>
  ${images}
</Ad>`;
}

function escapeXml(v: string) {
  return v.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
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

    const { data: settings, error: settingsErr } = await admin
      .from("immonova_portal_settings").select("enabled, credentials").eq("portal_key", "immobiliare_it").maybeSingle();
    if (settingsErr || !settings) {
      return jsonResponse({ success: false, error: "Impostazioni portale non trovate" }, 500);
    }
    if (!settings.enabled) {
      return jsonResponse({ success: false, error: "Pubblicazione su Immobiliare.it non attiva — configurala in Impostazioni Portali" }, 400);
    }

    const { username, password, source_id, agency_email, endpoint } = settings.credentials || {};
    if (!username || !password || !endpoint) {
      return jsonResponse({ success: false, error: "Credenziali Immobiliare.it incomplete (username/password/endpoint) — inseriscile in Impostazioni Portali" }, 400);
    }

    const basicAuth = "Basic " + btoa(`${username}:${password}`);

    let response: Response;
    let logMessage = "";

    if (action === "remove") {
      response = await fetch(`${endpoint}/${opportunity_id}`, {
        method: "DELETE",
        headers: { Authorization: basicAuth, "X-IMMO-SOURCE": source_id || "" },
      });
      logMessage = "Rimozione annuncio";
    } else {
      const { data: opp, error: oppErr } = await admin.from("opportunities").select("*").eq("id", opportunity_id).maybeSingle();
      if (oppErr || !opp) return jsonResponse({ success: false, error: "Opportunità non trovata" }, 404);

      const xml = buildXmlPayload(opp, agency_email || username);

      response = await fetch(endpoint, {
        method: "PUT",
        headers: {
          Authorization: basicAuth,
          "X-IMMO-SOURCE": source_id || "",
          "Content-Type": "application/xml; charset=utf-8",
        },
        body: xml,
      });
      logMessage = "Pubblicazione annuncio";
    }

    const responseText = await response.text();
    const ok = response.ok;

    await admin.from("immonova_portal_sync_log").insert({
      opportunity_id,
      portal_key: "immobiliare_it",
      status: ok ? "successo" : "errore",
      message: ok ? logMessage + " riuscita" : `${logMessage} fallita (HTTP ${response.status}): ${responseText.slice(0, 500)}`,
    });

    if (!ok) {
      return jsonResponse({ success: false, error: `Immobiliare.it ha risposto con errore (HTTP ${response.status})`, details: responseText }, 502);
    }

    return jsonResponse({ success: true }, 200);
  } catch (e) {
    return jsonResponse({ success: false, error: "Errore interno: " + String(e) }, 500);
  }
});
