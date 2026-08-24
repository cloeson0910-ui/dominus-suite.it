/* js/theme-loader.js — PRODOTTO WHITE-LABEL
   Legge immonova_theme_settings dal database e imposta variabili CSS globali
   (--primary-color, --text-color, ecc.) su :root, così ogni pagina che usa
   var(--...) invece di colori fissi si aggiorna automaticamente quando chi
   compra il prodotto personalizza i colori/font/sfondo dalla pagina admin
   "Aspetto" (admin/theme-settings.html), senza toccare una riga di codice.

   Stesso pattern di robustezza già usato in site-branding.js: crea un proprio
   client Supabase attendendo che window.supabase + config.js siano pronti,
   invece di dipendere dall'ordine in cui le pagine caricano gli script. */
(function(){
  var ownClient = null;
  function whenClientReady(cb){
    if(ownClient) return cb(ownClient);
    var tries = 0;
    var iv = setInterval(function(){
      tries++;
      if(window.supabase && typeof SUPABASE_URL !== "undefined" && typeof SUPABASE_ANON_KEY !== "undefined"){
        clearInterval(iv);
        ownClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
        cb(ownClient);
      }else if(tries > 100){
        clearInterval(iv);
      }
    }, 100);
  }

  function applyTheme(theme){
    if(!theme) return;

    var root = document.documentElement;
    root.style.setProperty("--primary-color", theme.primary_color || "#a67f34");
    root.style.setProperty("--secondary-color", theme.secondary_color || "#8a682c");
    root.style.setProperty("--text-color", theme.text_color || "#7f6430");
    root.style.setProperty("--page-bg-color", theme.page_bg_color || "#f4ecdf");
    root.style.setProperty("--menu-bg-color", theme.menu_bg_color || "rgba(244,236,223,.72)");
    root.style.setProperty("--menu-text-color", theme.menu_text_color || "#a67f34");
    root.style.setProperty("--font-family", theme.font_custom_name
      ? '"' + theme.font_custom_name + '", ' + (theme.font_family || "sans-serif")
      : (theme.font_family || '"Avenir Next","Helvetica Neue",Arial,sans-serif'));

    var styleTag = document.getElementById("immonova-theme-dynamic");
    if(!styleTag){
      styleTag = document.createElement("style");
      styleTag.id = "immonova-theme-dynamic";
      document.head.appendChild(styleTag);
    }

    var css = "";

    if(theme.font_custom_url && theme.font_custom_name){
      css += "@font-face{font-family:'" + theme.font_custom_name + "';src:url('" + theme.font_custom_url + "') format('woff2');font-display:swap;}\n";
    }

    // Sfondo pagina: quattro modalità gestite qui, tutte lette da variabili così
    // le pagine non devono sapere quale modalità è attiva. Il motivo a triangoli
    // (identità del brand originale) non è più un'opzione qui: default "none",
    // solo il colore di fondo pagina piatto.
    var mode = theme.background_mode || "none";
    if(mode === "pattern" || mode === "none" || mode === "solid"){
      css += "body::after{content:none;}\n";
    }else if(mode === "image" && theme.background_image_url){
      css += "body::after{content:'';position:fixed;inset:0;z-index:-1;" +
        "background:url('" + theme.background_image_url + "') center/cover no-repeat;opacity:1;}\n";
    }else{
      // 'solid' o 'none': nessun layer decorativo, solo il colore di fondo pagina
      // già impostato tramite --page-bg-color.
      css += "body::after{content:none;}\n";
    }

    styleTag.textContent = css;

    try{
      window.dispatchEvent(new CustomEvent("immonova-theme-ready", { detail: theme }));
    }catch(e){}
  }

  function loadTheme(){
    whenClientReady(function(client){
      client.from("immonova_theme_settings").select("*").eq("id", 1).single()
        .then(function(result){
          if(result.error){
            console.warn("Caricamento tema non riuscito (uso i valori di default):", result.error.message);
            applyTheme({});
            return;
          }
          applyTheme(result.data);
        })
        .catch(function(e){
          console.warn("Caricamento tema non riuscito (uso i valori di default):", e);
          applyTheme({});
        });
    });
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", loadTheme);
  }else{
    loadTheme();
  }

  window.immonovaThemeLoader = { applyTheme: applyTheme, reload: loadTheme };
})();
