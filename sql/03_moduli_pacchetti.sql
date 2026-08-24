-- ============================================================================
-- PRODOTTO WHITE-LABEL — Moduli attivabili/disattivabili, raggruppati in
-- pacchetti vendibili. Il Super Amministratore accende/spegne ogni modulo
-- da admin/feature-modules.html; il menu della dashboard si aggiorna da solo
-- (i link ai moduli spenti spariscono, senza toccare il codice).
--
-- NOTA IMPORTANTE: questa tabella governa i moduli per cui esiste già una
-- pagina/collegamento in QUESTA copia del sito. Molte delle 63 edge function
-- scaricate da immonova.it (discovery, valutazioni AI, tourism intelligence,
-- ecc.) non hanno ancora una pagina/collegamento costruiti qui — il modulo
-- corrispondente è elencato come "non ancora collegato" e va prima costruito
-- (pagina + collegamento) prima che il toggle abbia un effetto reale.
-- ============================================================================

create table if not exists public.immonova_modules (
  key text primary key,
  package_key text not null,
  package_label text not null,
  label text not null,
  description text,
  nav_href text,              -- pagina admin collegata (relativa a /admin/), null se non ancora costruita
  enabled boolean not null default true,
  built boolean not null default true,  -- false = funzione scaricata ma non ancora integrata in questa copia
  sort_order int not null default 0
);

insert into public.immonova_modules (key, package_key, package_label, label, description, nav_href, enabled, built, sort_order) values
  -- BASE (sempre inclusa, non disattivabile dal toggle ma elencata per chiarezza)
  ('crm_opportunita', 'base', 'Base', 'Opportunità', 'Gestione immobili/opportunità', 'opportunities.html', true, true, 10),
  ('crm_clienti', 'base', 'Base', 'Clienti', 'Investitori e venditori', 'investors.html', true, true, 20),
  ('crm_statistiche', 'base', 'Base', 'Statistiche', 'Dashboard numeri e andamento', 'statistics.html', true, true, 30),

  -- PACCHETTO CALENDARIO
  ('calendario', 'calendario', 'Calendario', 'Calendario collaboratori', 'Calendario condiviso, sync iCloud/Google', 'calendar.html', true, true, 100),

  -- PACCHETTO SOCIAL
  ('social_composer', 'social', 'Social', 'Composer Social', 'Creazione/pubblicazione post social', 'social-composer.html', true, true, 200),
  ('social_ads', 'social', 'Social', 'Gestione Pubblicità', 'Meta Ads / campagne', 'ads-manager.html', true, true, 210),
  ('social_ads_ab', 'social', 'Social', 'Test A/B Meta Ads', 'Pianificazione test A/B annunci', 'meta-ads-planner.html', true, true, 220),

  -- PACCHETTO NOTIFICHE
  ('notifiche_broadcast', 'notifiche', 'Notifiche', 'Notifiche Broadcast', 'Invio notifiche push a tutti gli iscritti', 'broadcast-notifications.html', true, true, 300),

  -- PACCHETTO DISCOVERY (funzioni scaricate, pagine da costruire)
  ('discovery_dati', 'discovery', 'Discovery', 'Fonti Dati', 'Sorgenti dati automatiche per le destinazioni', 'data-sources.html', true, true, 400),
  ('discovery_foto', 'discovery', 'Discovery', 'Foto Destinazioni', 'Libreria foto delle destinazioni', 'destination-photos.html', true, true, 410),
  ('discovery_verificati', 'discovery', 'Discovery', 'Dati Verificati', 'Override manuali su dati automatici', 'manual-overrides.html', true, true, 420),
  ('discovery_engine', 'discovery', 'Discovery', 'Motore Discovery avanzato', 'Intelligence su POI, patrimonio, costa, accessibilità, turismo', null, false, false, 430),

  -- PACCHETTO VALUTAZIONI AI (funzioni scaricate, pagine da costruire/collegare)
  ('valutazioni', 'valutazioni', 'Valutazioni AI', 'Valutazioni Immobiliari', 'Report di valutazione assistiti da AI', 'valuations.html', true, true, 500),

  -- PACCHETTO COMUNICAZIONI
  ('comunicazioni_email', 'comunicazioni', 'Comunicazioni', 'Comunicazioni', 'Composer email verso investitori/clienti', 'email-composer.html', true, true, 600),

  -- PACCHETTO APP/RESPONSIVE (strumenti, spesso lasciati sempre attivi)
  ('app_responsive_preview', 'app', 'App', 'Anteprima Responsive', 'Anteprima del sito su vari dispositivi', 'responsive-preview.html', true, true, 700),

  -- PACCHETTO EVENTI & CRM AVANZATO
  ('eventi', 'eventi_crm', 'Eventi & CRM avanzato', 'Eventi', 'Gestione eventi', 'events.html', true, true, 800),
  ('mandati_ricerca', 'eventi_crm', 'Eventi & CRM avanzato', 'Mandati di Ricerca', 'Richieste di ricerca immobiliare da investitori', 'search-mandates.html', true, true, 810),
  ('capital_partners', 'eventi_crm', 'Eventi & CRM avanzato', 'Capital Partners', 'Sezione riservata investitori istituzionali', 'capital-partners.html', true, true, 820)
on conflict (key) do nothing;

alter table public.immonova_modules enable row level security;

drop policy if exists "modules_select" on public.immonova_modules;
create policy "modules_select" on public.immonova_modules for select to authenticated using (true);

-- Scrittura riservata al super_admin (stesso pattern di roles-permissions).
drop policy if exists "modules_write_super_admin" on public.immonova_modules;
create policy "modules_write_super_admin" on public.immonova_modules for update to authenticated
  using (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id = p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ))
  with check (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id = p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ));

select package_label, label, enabled, built, nav_href from public.immonova_modules order by sort_order;
