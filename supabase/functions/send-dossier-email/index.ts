// Supabase Edge Function: send-dossier-email
// Invia al cliente il dossier PDF già generato e caricato su Supabase Storage
// (bucket "dossier-pdfs"), in allegato, con copia di conferma all'amministrazione.
//
// Input atteso (JSON):
// {
//   to: string,              // email del cliente destinatario
//   cc: string,               // email copia conferma (amministrazione)
//   client_name: string,      // nome cliente (solo per il corpo della mail, opzionale)
//   opportunity_title: string,
//   pdf_url: string,          // URL pubblico Supabase Storage del PDF già caricato
//   filename: string,         // nome file, es. dossier_DOMINUS_Martina_Franca.pdf
//   language: string,         // "it" | "en" | altro -> fallback italiano
//   attachments: [            // opzionale: allegati aggiuntivi (Privacy/NDA), già
//     { url: string, filename: string }   // nella lingua corretta lato client
//   ]
// }
//
// LEZIONE CRITICA del progetto (vedi memoria): quando questa funzione risponde con status
// non-2xx, supabase-js sul client NON mette il body JSON in result.data — resta null — e
// result.error.message è sempre il testo fisso generico. Il messaggio vero va letto da
// result.error.context. Per questo qui restituiamo SEMPRE un body JSON leggibile
// { success, error } sia su successo che su errore, in modo che extractEdgeFunctionErrorMessage
// lato client (dossier-send.html) riesca a mostrare la causa vera.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_ADDRESS = "DOMINUS <noreply@dominus-suite.it>";

function jsonResponse(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode.apply(null, Array.from(chunk) as number[]);
  }
  return btoa(binary);
}

function buildDominusEmailHtml(title: string, innerHtml: string): string {
  return "" +
    "<div style=\"background:#f4ecdf;padding:40px 20px;font-family:'Avenir Next','Helvetica Neue',Arial,sans-serif;\">" +
      "<div style=\"max-width:560px;margin:0 auto;background:#ffffff;border:1px solid rgba(166,127,52,.25);\">" +
        "<div style=\"padding:36px 40px 24px;text-align:center;border-bottom:1px solid rgba(166,127,52,.15);\">" +
          "<div style=\"font-size:24px;font-weight:600;letter-spacing:.35em;color:#a67f34;\">DOMINUS</div>" +
          "<div style=\"margin-top:8px;font-size:10px;font-weight:700;letter-spacing:.2em;color:#a58139;text-transform:uppercase;\">Off Market &middot; Consulting</div>" +
        "</div>" +
        "<div style=\"padding:36px 40px;\">" +
          "<h1 style=\"margin:0 0 20px;font-size:19px;font-weight:400;color:#a67f34;\">" + title + "</h1>" +
          innerHtml +
        "</div>" +
        "<div style=\"padding:24px 40px;border-top:1px solid rgba(166,127,52,.15);text-align:center;\">" +
          "<div style=\"font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:#8f7643;\">DOMINUS &middot; Off Market Consulting</div>" +
        "</div>" +
      "</div>" +
    "</div>";
}

function emailBody(clientName: string, opportunityTitle: string, language: string) {
  const isEnglish = String(language || "it").toLowerCase().startsWith("en");
  const greetingName = clientName ? clientName : (isEnglish ? "Investor" : "Gentile investitore");
  const pStyle = "margin:0 0 16px;font-size:15px;line-height:1.7;color:#4a3c1f";

  if (isEnglish) {
    const innerHtml =
      "<p style=\"" + pStyle + "\">Dear " + escapeHtml(greetingName) + ",</p>" +
      "<p style=\"" + pStyle + "\">Please find attached the confidential investment dossier for <strong>" + escapeHtml(opportunityTitle) + "</strong>.</p>" +
      "<p style=\"" + pStyle + "\">This document is confidential and subject to the NDA and privacy terms you accepted when requesting it. Please do not share it with third parties without written authorization from DOMINUS Off Market Consulting.</p>" +
      "<p style=\"" + pStyle + "\">Should you have any questions, feel free to reply to this email.</p>" +
      "<p style=\"" + pStyle + "\">Best regards,<br>DOMINUS Off Market Consulting</p>";
    return {
      subject: "Your Confidential Investment Dossier — " + opportunityTitle,
      html: buildDominusEmailHtml("Confidential Investment Dossier", innerHtml),
    };
  }

  const innerHtmlIt =
    "<p style=\"" + pStyle + "\">Gentile " + escapeHtml(greetingName) + ",</p>" +
    "<p style=\"" + pStyle + "\">In allegato trova il dossier riservato di investimento per <strong>" + escapeHtml(opportunityTitle) + "</strong>.</p>" +
    "<p style=\"" + pStyle + "\">Il documento è confidenziale ed è soggetto ai termini di NDA e privacy accettati in fase di richiesta. La preghiamo di non condividerlo con terzi senza autorizzazione scritta di DOMINUS Off Market Consulting.</p>" +
    "<p style=\"" + pStyle + "\">Per qualsiasi domanda può rispondere direttamente a questa email.</p>" +
    "<p style=\"" + pStyle + "\">Cordiali saluti,<br>DOMINUS Off Market Consulting</p>";

  return {
    subject: "Il tuo Dossier Riservato DOMINUS — " + opportunityTitle,
    html: buildDominusEmailHtml("Dossier Riservato DOMINUS", innerHtmlIt),
  };
}

function escapeHtml(value: string): string {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Metodo non consentito, usare POST." }, 405);
  }

  if (!RESEND_API_KEY) {
    return jsonResponse({ success: false, error: "RESEND_API_KEY non configurato tra i secret della edge function." }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ success: false, error: "Corpo della richiesta non è JSON valido." }, 400);
  }

  const to = String(body.to || "").trim();
  const cc = String(body.cc || "").trim();
  const clientName = String(body.client_name || "").trim();
  const opportunityTitle = String(body.opportunity_title || "Opportunità DOMINUS").trim();
  const pdfUrl = String(body.pdf_url || "").trim();
  const filename = String(body.filename || "dossier_DOMINUS.pdf").trim();
  const language = String(body.language || "it").trim();

  const rawAttachments = Array.isArray(body.attachments) ? body.attachments : [];
  const extraAttachmentRequests: { url: string; filename: string }[] = rawAttachments
    .map((a: Record<string, unknown>) => ({
      url: String((a && a.url) || "").trim(),
      filename: String((a && a.filename) || "").trim() || "allegato.pdf",
    }))
    .filter((a) => !!a.url);

  if (!to) {
    return jsonResponse({ success: false, error: "Campo 'to' (email cliente) mancante." }, 400);
  }
  if (!pdfUrl) {
    return jsonResponse({ success: false, error: "Campo 'pdf_url' mancante: nessun PDF da allegare." }, 400);
  }

  let pdfBase64: string;
  try {
    const pdfRes = await fetch(pdfUrl);
    if (!pdfRes.ok) {
      return jsonResponse({
        success: false,
        error: "Impossibile scaricare il PDF da Storage (HTTP " + pdfRes.status + "). Verificare che il bucket 'dossier-pdfs' sia pubblico e l'URL corretto.",
      }, 502);
    }
    const buffer = await pdfRes.arrayBuffer();
    if (!buffer || buffer.byteLength === 0) {
      return jsonResponse({ success: false, error: "Il PDF scaricato da Storage è vuoto." }, 502);
    }
    pdfBase64 = arrayBufferToBase64(buffer);
  } catch (e) {
    return jsonResponse({ success: false, error: "Errore durante il download del PDF da Storage: " + (e?.message || e) }, 502);
  }

  // Allegati aggiuntivi (Privacy Policy / NDA nella lingua del dossier). Se uno di
  // questi fallisce non blocchiamo l'invio dell'email col dossier principale: lo
  // segnaliamo solo nella risposta finale come warning, per non perdere l'invio
  // per un problema su un allegato secondario.
  const extraAttachments: { filename: string; content: string }[] = [];
  const attachmentWarnings: string[] = [];
  for (const att of extraAttachmentRequests) {
    try {
      const res = await fetch(att.url);
      if (!res.ok) {
        attachmentWarnings.push("Allegato '" + att.filename + "' non scaricato (HTTP " + res.status + ").");
        continue;
      }
      const buf = await res.arrayBuffer();
      if (!buf || buf.byteLength === 0) {
        attachmentWarnings.push("Allegato '" + att.filename + "' scaricato vuoto, ignorato.");
        continue;
      }
      extraAttachments.push({ filename: att.filename, content: arrayBufferToBase64(buf) });
    } catch (e) {
      attachmentWarnings.push("Allegato '" + att.filename + "' non scaricato: " + (e?.message || e));
    }
  }

  const { subject, html } = emailBody(clientName, opportunityTitle, language);

  const resendPayload: Record<string, unknown> = {
    from: FROM_ADDRESS,
    to: [to],
    subject,
    html,
    attachments: [
      {
        filename,
        content: pdfBase64,
      },
      ...extraAttachments,
    ],
  };
  if (cc) {
    resendPayload.cc = [cc];
  }

  try {
    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + RESEND_API_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(resendPayload),
    });

    const resendRaw = await resendRes.text();
    let resendJson: Record<string, unknown> | null = null;
    try {
      resendJson = resendRaw ? JSON.parse(resendRaw) : null;
    } catch (_e) {
      // risposta non JSON, gestita sotto con resendRaw grezzo
    }

    if (!resendRes.ok) {
      const resendErrorMessage = (resendJson && (resendJson.message || resendJson.error)) || resendRaw || "Errore sconosciuto da Resend.";
      return jsonResponse({
        success: false,
        error: "Resend ha rifiutato l'invio (HTTP " + resendRes.status + "): " + resendErrorMessage,
      }, 502);
    }

    return jsonResponse({
      success: true,
      resend_id: (resendJson && resendJson.id) || null,
      attachment_warnings: attachmentWarnings.length ? attachmentWarnings : undefined,
    }, 200);
  } catch (e) {
    return jsonResponse({ success: false, error: "Chiamata a Resend fallita prima di ricevere risposta: " + (e?.message || e) }, 502);
  }
});
