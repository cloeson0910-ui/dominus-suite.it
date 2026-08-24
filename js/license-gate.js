// SITO CLIENTE — js/license-gate.js
// Controlla la licenza del sito presso il pannello centrale. Va incluso in
// dashboard.html (già fatto in fondo a questo file trovi l'istruzione) e
// gira PRIMA di mostrare qualunque contenuto della dashboard.
//
// Se il pacchetto base non è pagato/attivo -> reindirizza a license-expired.html
// Se un pacchetto aggiuntivo non è pagato -> lo nasconde dal menu, anche se
// il toggle locale in immonova_modules dice "enabled" (il cliente non può
// riattivarsi da solo un pacchetto che non paga più).
//
// Controlla una volta per sessione (salvato in sessionStorage) per non
// rallentare ogni caricamento pagina — comunque ricontrolla ad ogni nuovo
// login/apertura del browser.

(function () {
  const CONTROL_PLANE_URL = "https://cspzkofhgfrnkhjpfazb.supabase.co"; // guestintown, stesso progetto di js/config.js
  const CONTROL_PLANE_ANON_KEY = "sb_publishable_oYbR_A78f8SRKdJbkeZegQ_4gAx-567";

  async function getLicenseCode(supabaseClient) {
    const { data } = await supabaseClient.from("immonova_license").select("license_code").eq("id", 1).maybeSingle();
    return data?.license_code || null;
  }

  async function verifyLicense(licenseCode) {
    const res = await fetch(CONTROL_PLANE_URL + "/functions/v1/license-verify", {
      method: "POST",
      headers: { "Content-Type": "application/json", "apikey": CONTROL_PLANE_ANON_KEY },
      body: JSON.stringify({ license_code: licenseCode }),
    });
    return res.json();
  }

  window.immonovaLicenseGate = {
    // Chiamata da dashboard.html appena il client Supabase è pronto.
    // Ritorna { blocked: boolean, enabledPackages: string[] }
    async check(supabaseClient) {
      const cached = sessionStorage.getItem("immonova_license_check");
      if (cached) {
        try { return JSON.parse(cached); } catch (e) { /* ricontrolla */ }
      }

      const licenseCode = await getLicenseCode(supabaseClient);
      if (!licenseCode) {
        // Nessuna licenza mai attivata su questo sito -> vai alla pagina di attivazione.
        window.location.href = "license-activation.html";
        return { blocked: true, enabledPackages: [] };
      }

      let result;
      try {
        result = await verifyLicense(licenseCode);
      } catch (e) {
        // Se il pannello centrale non è raggiungibile (rete giù, ecc.), non
        // blocchiamo il cliente per un problema nostro: lasciamo passare,
        // ma senza salvare in cache così ricontrolla al prossimo giro.
        console.warn("Verifica licenza non riuscita (rete):", e);
        return { blocked: false, enabledPackages: null };
      }

      if (!result.valid) {
        window.location.href = "license-expired.html?motivo=" + encodeURIComponent(result.reason || "");
        return { blocked: true, enabledPackages: [] };
      }

      const outcome = { blocked: false, enabledPackages: result.enabled_packages || [] };
      sessionStorage.setItem("immonova_license_check", JSON.stringify(outcome));
      return outcome;
    },
  };
})();
