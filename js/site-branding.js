/* DOMINUS — Logo e contatti centralizzati (letti dal database, non più scritti nel
   codice). Da includere in ogni pagina DOPO js/config.js:
     <script src="js/config.js"></script>
     <script src="js/site-branding.js"></script>
   (regola il percorso "js/..." in base alla profondità della pagina, come già si fa
   per config.js — es. "../js/site-branding.js" dentro /admin).

   Cosa fa automaticamente, senza bisogno di scrivere altro codice nella pagina:
   - Ogni elemento con class="logo" (il testo "DOMINUS" usato come logo in tutte le
     pagine) viene sostituito con l'immagine caricata dalla pagina admin, SE è stata
     caricata. Se non è stato caricato nessun logo, resta il testo originale invariato
     (nessuna rottura visiva).
   - Ogni elemento con l'attributo data-site-contact="emails" | "phones" | "addresses"
     | "full" viene riempito con i dati letti dal database. Vedi i commenti sotto le
     funzioni render* per il formato di ciascuno.

   Se una pagina non ha nessuno di questi hook, questo script non fa nulla (nessun
   effetto collaterale) tranne una singola query leggera al database. */
(function(){
  /* Non si affida a window.supabaseClient: su alcune pagine l'ordine di caricamento tra
     config.js e la libreria Supabase da CDN è invertito (bug pre-esistente, non toccato
     qui) e quel client potrebbe non essere mai stato creato. Crea un proprio client
     "di sola lettura" appena la libreria (window.supabase) e le costanti da config.js
     (SUPABASE_URL/SUPABASE_ANON_KEY) sono entrambe disponibili, indipendentemente
     dall'ordine con cui sono stati inclusi gli script. */
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
      }else if(tries > 100){ clearInterval(iv); } // ~10s, poi rinuncia silenziosamente
    }, 100);
  }

  function escapeHTML(value){
    return String(value == null ? "" : value)
      .replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;")
      .replaceAll('"',"&quot;").replaceAll("'","&#039;");
  }

  function renderLogo(settings){
    if(!settings || !settings.logo_url) return;
    document.querySelectorAll(".logo").forEach(function(el){
      // Se dentro c'e' gia' un tag <img> (pagina gia' aggiornata a mano), non tocca nulla.
      if(el.querySelector("img")) return;
      var img = document.createElement("img");
      img.src = settings.logo_url;
      img.alt = settings.company_name || "DOMINUS";
      img.style.maxHeight = "38px";
      img.style.maxWidth = "220px";
      img.style.width = "auto";
      img.style.height = "auto";
      img.style.display = "block";
      el.innerHTML = "";
      el.appendChild(img);
    });
  }

  /* data-site-contact="emails": lista di indirizzi email cliccabili (mailto:), separati
     da virgola, oppure uno per riga se l'elemento ha anche data-site-contact-list="block". */
  function renderEmails(container, emails){
    if(!emails.length){ container.innerHTML = ""; return; }
    var asBlock = container.getAttribute("data-site-contact-list") === "block";
    var sep = asBlock ? "<br>" : ", ";
    container.innerHTML = emails.map(function(e){
      var label = e.label ? escapeHTML(e.label) + ": " : "";
      return label + '<a href="mailto:' + escapeHTML(e.email) + '">' + escapeHTML(e.email) + '</a>';
    }).join(sep);
  }

  /* data-site-contact="phones": lista di telefoni cliccabili (tel:). */
  function renderPhones(container, phones){
    if(!phones.length){ container.innerHTML = ""; return; }
    var asBlock = container.getAttribute("data-site-contact-list") === "block";
    var sep = asBlock ? "<br>" : ", ";
    container.innerHTML = phones.map(function(p){
      var label = p.label ? escapeHTML(p.label) + ": " : "";
      var telHref = "tel:" + String(p.phone).replace(/[^0-9+]/g, "");
      return label + '<a href="' + telHref + '">' + escapeHTML(p.phone) + '</a>';
    }).join(sep);
  }

  /* data-site-contact="addresses": elenco indirizzi (solo testo, senza i telefoni). */
  function renderAddresses(container, addresses){
    if(!addresses.length){ container.innerHTML = ""; return; }
    container.innerHTML = addresses.map(function(a){
      var label = a.label ? "<strong>" + escapeHTML(a.label) + "</strong><br>" : "";
      return "<div>" + label + escapeHTML(a.address) + "</div>";
    }).join("");
  }

  /* data-site-contact="full": blocco completo pensato per un footer -- ogni indirizzo
     con i suoi telefoni sotto, poi le email in fondo. */
  function renderFull(container, data){
    var html = "";
    data.addresses.forEach(function(a){
      var phonesForAddress = data.phones.filter(function(p){ return p.address_id === a.id; });
      html += "<div style='margin-bottom:10px'>";
      if(a.label) html += "<strong>" + escapeHTML(a.label) + "</strong><br>";
      html += escapeHTML(a.address);
      if(phonesForAddress.length){
        html += "<br>" + phonesForAddress.map(function(p){
          var label = p.label ? escapeHTML(p.label) + ": " : "";
          var telHref = "tel:" + String(p.phone).replace(/[^0-9+]/g, "");
          return label + '<a href="' + telHref + '">' + escapeHTML(p.phone) + '</a>';
        }).join(" · ");
      }
      html += "</div>";
    });
    if(data.emails.length){
      html += "<div>" + data.emails.map(function(e){
        return '<a href="mailto:' + escapeHTML(e.email) + '">' + escapeHTML(e.email) + '</a>';
      }).join(" · ") + "</div>";
    }
    container.innerHTML = html;
  }

  function applyContactHooks(data){
    document.querySelectorAll('[data-site-contact="emails"]').forEach(function(el){ renderEmails(el, data.emails); });
    document.querySelectorAll('[data-site-contact="phones"]').forEach(function(el){ renderPhones(el, data.phones); });
    document.querySelectorAll('[data-site-contact="addresses"]').forEach(function(el){ renderAddresses(el, data.addresses); });
    document.querySelectorAll('[data-site-contact="full"]').forEach(function(el){ renderFull(el, data); });
  }

  whenClientReady(function(client){
    Promise.all([
      client.from("immonova_site_settings").select("logo_url,company_name").eq("id", 1).single(),
      client.from("immonova_contact_emails").select("email,label,is_primary,sort_order").eq("active", true).order("sort_order"),
      client.from("immonova_contact_addresses").select("id,label,address,is_primary,sort_order").eq("active", true).order("sort_order"),
      client.from("immonova_contact_phones").select("id,address_id,phone,label,sort_order").eq("active", true).order("sort_order"),
    ]).then(function(results){
      var settings = results[0] && results[0].data;
      var emails = (results[1] && results[1].data) || [];
      var addresses = (results[2] && results[2].data) || [];
      var phones = (results[3] && results[3].data) || [];

      renderLogo(settings);
      applyContactHooks({ emails:emails, addresses:addresses, phones:phones });

      window.immonovaSiteBranding = { settings:settings, emails:emails, addresses:addresses, phones:phones };
      document.dispatchEvent(new CustomEvent("immonova-site-branding-ready", { detail:window.immonovaSiteBranding }));
    }).catch(function(e){
      console.error("site-branding: caricamento impostazioni sito non riuscito", e);
    });
  });
})();
