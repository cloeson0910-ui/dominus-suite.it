const SUPABASE_URL = "https://cspzkofhgfrnkhjpfazb.supabase.co";

const SUPABASE_ANON_KEY = "sb_publishable_oYbR_A78f8SRKdJbkeZegQ_4gAx-567";

// Multi-tenant: ogni cliente/demo ha il suo sottodominio, es.
// "nomecliente.dominus-suite.it". Il "tenant slug" è la prima parte
// dell'indirizzo (tutto prima del primo punto), e viene mandato ad ogni
// chiamata Supabase con l'header "x-tenant-slug" — così il database sa
// SEMPRE per conto di quale cliente sta rispondendo, anche per i
// visitatori anonimi (form pubblici, pagine senza login).
//
// In locale (localhost) o su un dominio "diretto" senza sottodominio
// personalizzato, usa "demo" come tenant di default — evita di rompere
// l'anteprima durante lo sviluppo.
function getTenantSlug() {
  var host = window.location.hostname;
  if (host === "localhost" || host === "127.0.0.1") return "demo";
  var parts = host.split(".");
  // "nomecliente.dominus-suite.it" -> ["nomecliente","dominus-suite","it"] -> "nomecliente"
  // "dominus-suite.it" (senza sottodominio) -> fallback "demo"
  if (parts.length <= 2) return "demo";
  return parts[0];
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
