/* js/welcome-demo.js — messaggio di benvenuto dopo l'attivazione della demo.
   Va incluso in dashboard.html (dopo js/config.js), non fa nulla se non
   trova il segnale "?benvenuto=1" nel link — quindi è sicuro includerlo
   sempre, appare solo la prima volta, subito dopo l'attivazione. */
(function () {
  var params = new URLSearchParams(window.location.search);
  if (params.get("benvenuto") !== "1") return;

  // Pulisce subito il link (niente "?benvenuto=1" se l'utente lo ricarica
  // o lo condivide), il messaggio resta comunque a video finché non lo chiude.
  var cleanUrl = window.location.pathname;
  window.history.replaceState({}, "", cleanUrl);

  var overlay = document.createElement("div");
  overlay.style.cssText = "position:fixed;inset:0;z-index:9999;background:rgba(20,17,13,.55);display:flex;align-items:center;justify-content:center;padding:24px;";

  var box = document.createElement("div");
  box.style.cssText = "background:#FBF8F0;max-width:480px;width:100%;padding:40px 36px;box-shadow:0 20px 60px rgba(0,0,0,.3);text-align:center;font-family:var(--font-family,\"Avenir Next\",\"Helvetica Neue\",Arial,sans-serif);";

  box.innerHTML =
    '<div style="font-family:\'Fraunces\',Georgia,serif;font-style:italic;font-size:28px;color:#14110D;margin-bottom:6px;">Benvenuto in Dominus</div>' +
    '<div style="width:36px;height:1px;background:var(--primary-color,#a67f34);margin:14px auto 22px;"></div>' +
    '<p style="font-size:14px;line-height:1.7;color:#3A362E;margin-bottom:16px;">La tua demo è ora completamente sbloccata: puoi esplorare liberamente ogni funzione del gestionale, esattamente come farebbe un cliente Dominus a tutti gli effetti.</p>' +
    '<p style="font-size:14px;line-height:1.7;color:#3A362E;margin-bottom:16px;">Le due funzioni più curate — <strong>generazione dossier</strong> e <strong>valutazione con intelligenza artificiale</strong> — sono disponibili <strong>una volta ciascuna</strong> in questa prova, così puoi valutarne davvero la qualità prima di scegliere il pacchetto più adatto a te.</p>' +
    '<p style="font-size:14px;line-height:1.7;color:#3A362E;margin-bottom:28px;">Ti consigliamo di dare un\'occhiata alle <strong>video guide</strong> prima di iniziare: in pochi minuti avrai chiaro come muoverti in ogni sezione, senza sorprese.</p>' +
    '<div style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap;">' +
      '<a href="videoguide.html" style="background:#14110D;color:#F2ECDE;padding:13px 22px;text-decoration:none;font-size:12px;letter-spacing:.08em;text-transform:uppercase;">Guarda le video guide</a>' +
      '<button id="welcomeDemoClose" style="background:none;border:1px solid rgba(60,50,30,.3);color:#3A362E;padding:13px 22px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;cursor:pointer;font-family:inherit;">Inizia subito</button>' +
    '</div>';

  overlay.appendChild(box);
  document.body.appendChild(overlay);

  function close() { overlay.remove(); }
  box.querySelector("#welcomeDemoClose").addEventListener("click", close);
  overlay.addEventListener("click", function (e) { if (e.target === overlay) close(); });
})();
