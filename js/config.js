const SUPABASE_URL = "https://cspzkofhgfrnkhjpfazb.supabase.co";

const SUPABASE_ANON_KEY = "sb_publishable_oYbR_A78f8SRKdJbkeZegQ_4gAx-567";

// Multi-tenant: il sito è UNO SOLO (es. app.dominus-suite.it), condiviso da
// tutte le demo/clienti. Il "tenant" (di quale cliente sono i dati che sto
// mostrando) si riconosce così, in ordine:
//   1) parametro "?t=nomecliente" nel link (quello mandato al lead la prima
//      volta, es. https://app.dominus-suite.it/?t=villa-fiore)
//   2) se non c'è nel link, quello salvato in questo browser da una visita
//      precedente (così non serve rimetterlo in OGNI pagina interna)
//   3) altrimenti "demo" di default (evita di rompere l'anteprima)
// Il tenant scelto viene mandato ad OGNI chiamata Supabase con l'header
// "x-tenant-slug", così il database sa sempre per conto di chi sta
// rispondendo — anche per visitatori anonimi (form pubblici, senza login).
function getTenantSlug() {
  var params = new URLSearchParams(window.location.search);
  var fromUrl = params.get("t");
  if (fromUrl) {
    try { localStorage.setItem("dominus_tenant_slug", fromUrl); } catch (e) {}
    return fromUrl;
  }
  try {
    var saved = localStorage.getItem("dominus_tenant_slug");
    if (saved) return saved;
  } catch (e) {}
  return "demo";
}

window.CURRENT_TENANT_SLUG = getTenantSlug();

window.supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  {
    global: {
      headers: { "x-tenant-slug": window.CURRENT_TENANT_SLUG }
    }
  }
);
