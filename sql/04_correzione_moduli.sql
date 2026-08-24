-- ============================================================================
-- CORREZIONE catalogo moduli, dopo il controllo completo delle 56 edge
-- function esportate da immonova.it contro le pagine/moduli già presenti
-- nella copia whitelabel.
--
-- Trovato:
-- 1) "discovery_engine" era registrato come UN modulo, ma in realtà
--    raggruppa 14 motori distinti (POI, patrimonio, costa, accessibilità,
--    demografia, destinazioni, evidenze, dati globali, turismo x2, rating
--    investimento, market intelligence live, profilo location, classificatore
--    AI). Descrizione aggiornata per riflettere il valore reale.
-- 2) "Dossier & Report" era un pacchetto già costruito e funzionante
--    (dossier-send.html + report-view.html, con invio email e generazione
--    report AI) ma MAI registrato in immonova_modules: invisibile al
--    super_admin, non vendibile, non presente nel menu. Aggiunto ora.
-- ============================================================================

update public.immonova_modules
set
  label = 'Motore Discovery Intelligence',
  description = 'Suite di 14 motori di analisi territoriale: POI, patrimonio, costa, accessibilità, demografia, destinazioni, evidenze, dati globali, turismo (x2), rating investimento, market intelligence live, profilo location, classificatore AI. Richiede una pagina dedicata prima di essere attivabile.'
where key = 'discovery_engine';

insert into public.immonova_modules (key, package_key, package_label, label, description, nav_href, enabled, built, sort_order) values
  ('dossier_report', 'dossier', 'Dossier & Report', 'Dossier & Report Investimento', 'Generazione e invio di dossier/report di investimento (PDF, narrativa AI, traduzione, promemoria follow-up)', 'dossier-send.html', true, true, 900)
on conflict (key) do update set
  package_key = excluded.package_key,
  package_label = excluded.package_label,
  label = excluded.label,
  description = excluded.description,
  nav_href = excluded.nav_href,
  built = excluded.built;

select package_label, label, enabled, built, nav_href from public.immonova_modules order by sort_order;
