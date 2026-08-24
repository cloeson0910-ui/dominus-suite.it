/* DOMINUS — Meta Pixel + Google Analytics inizializzati dinamicamente leggendo l'ID dal
   database (immonova_site_settings), invece di essere scritti a mano in ogni pagina.

   Da includere in ogni pagina PUBBLICA, dentro <head>, dopo js/config.js:
     <script src="js/config.js"></script>
     <script src="js/site-analytics.js"></script>

   NOTA sul timing: rispetto agli script hardcoded che partivano appena il browser
   leggeva l'HTML, qui il pixel/GA partono un istante dopo (il tempo di una query al
   database) -- impercettibile per l'utente, ma tecnicamente il primo "PageView" viene
   inviato con qualche decina di millisecondi di ritardo invece che a caricamento zero.
   Se in futuro questo ritardo diventa un problema si può aggiungere una cache in
   localStorage per evitare la query ad ogni visita. */
(function(){
  // Vedi il commento equivalente in site-branding.js: non si affida a
  // window.supabaseClient (può non esistere per un bug pre-esistente di ordine degli
  // script su alcune pagine), crea un proprio client appena possibile.
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
      }else if(tries > 100){ clearInterval(iv); }
    }, 100);
  }

  function initMetaPixel(pixelId){
    if(!pixelId) return;
    !function(f,b,e,v,n,t,s)
    {if(f.fbq)return;n=f.fbq=function(){n.callMethod?
    n.callMethod.apply(n,arguments):n.queue.push(arguments)};
    if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
    n.queue=[];t=b.createElement(e);t.async=!0;
    t.src=v;s=b.getElementsByTagName(e)[0];
    s.parentNode.insertBefore(t,s)}(window,document,'script',
    'https://connect.facebook.net/en_US/fbevents.js');
    window.fbq('init', pixelId);
    window.fbq('track', 'PageView');
  }

  function initGoogleAnalytics(measurementId){
    if(!measurementId) return;
    var script = document.createElement("script");
    script.async = true;
    script.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(measurementId);
    document.head.appendChild(script);

    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function(){ window.dataLayer.push(arguments); };
    window.gtag('js', new Date());
    window.gtag('config', measurementId);
  }

  whenClientReady(function(client){
    client.from("immonova_site_settings").select("meta_pixel_id,ga_measurement_id").eq("id", 1).single()
      .then(function(result){
        var data = result && result.data;
        if(!data) return;
        initMetaPixel(data.meta_pixel_id);
        initGoogleAnalytics(data.ga_measurement_id);
      })
      .catch(function(e){ console.error("site-analytics: caricamento non riuscito", e); });
  });
})();
