-- ============================================================================
-- PUBBLICAZIONE SU PORTALI (Immobiliare.it, Idealista) — da eseguire dopo
-- 05_licenza.sql su ogni progetto Supabase di ciascun sito cliente.
--
-- Le credenziali sono per singolo sito: ogni agenzia usa il PROPRIO
-- contratto con i portali, non quello di Immonova. Nota su Subito.it: da
-- aprile 2026 gli annunci pubblicati su Immobiliare.it vengono ripubblicati
-- automaticamente anche su Subito in 9 regioni (Lombardia, Lazio, Veneto,
-- Piemonte, Emilia-Romagna, Toscana, Campania, Liguria, Umbria) — nessuna
-- integrazione separata necessaria per Subito.
-- ============================================================================

create table if not exists public.immonova_portal_settings (
  portal_key text primary key,     -- 'immobiliare_it', 'idealista'
  enabled boolean not null default false,
  credentials jsonb not null default '{}'::jsonb,  -- es. {"username":"...","password":"...","source_id":"..."}
  updated_at timestamptz not null default now()
);

insert into public.immonova_portal_settings (portal_key, enabled) values
  ('immobiliare_it', false),
  ('idealista', false)
on conflict (portal_key) do nothing;

alter table public.immonova_portal_settings enable row level security;

drop policy if exists "portal_settings_super_admin_all" on public.immonova_portal_settings;
create policy "portal_settings_super_admin_all" on public.immonova_portal_settings for all to authenticated
  using (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id = p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ))
  with check (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id = p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ));

-- ---------------------------------------------------------------------------
-- Su ogni opportunità: quali portali deve raggiungere, e l'esito dell'ultimo
-- tentativo di pubblicazione per ciascuno (per mostrare errori in dashboard).
-- ---------------------------------------------------------------------------
alter table public.opportunities
  add column if not exists publish_immobiliare_it boolean not null default false,
  add column if not exists publish_idealista boolean not null default false;

create table if not exists public.immonova_portal_sync_log (
  id uuid primary key default gen_random_uuid(),
  opportunity_id bigint not null references public.opportunities(id) on delete cascade,
  portal_key text not null,
  status text not null check (status in ('successo','errore')),
  message text,
  synced_at timestamptz not null default now()
);

alter table public.immonova_portal_sync_log enable row level security;

drop policy if exists "portal_sync_log_read" on public.immonova_portal_sync_log;
create policy "portal_sync_log_read" on public.immonova_portal_sync_log for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Registra il nuovo pacchetto in Moduli e Pacchetti (admin/feature-modules.html)
-- ---------------------------------------------------------------------------
insert into public.immonova_modules (key, package_key, package_label, label, description, nav_href, enabled, built, sort_order) values
  ('portali_immobiliari', 'portali', 'Portali Immobiliari', 'Portali Immobiliari', 'Pubblicazione annunci su Immobiliare.it (con ripubblicazione automatica su Subito.it) e Idealista', 'portali-immobiliari.html', true, true, 950)
on conflict (key) do update set
  package_key = excluded.package_key,
  package_label = excluded.package_label,
  label = excluded.label,
  description = excluded.description,
  nav_href = excluded.nav_href;

select 'Impostazioni portali create.' as esito;
