-- ============================================================================
-- PRODOTTO WHITE-LABEL — Temi personalizzabili (colori, font, sfondo)
-- Da eseguire SOLO sul progetto Supabase del nuovo prodotto/copia, MAI su
-- quello di immonova.it in produzione.
-- ============================================================================

create table if not exists public.immonova_theme_settings (
  id bigint primary key default 1,
  -- Colori principali
  primary_color text not null default '#a67f34',      -- colore brand principale (link, bottoni, accenti)
  secondary_color text not null default '#8a682c',     -- variante hover/scura del principale
  text_color text not null default '#7f6430',          -- colore testo principale
  page_bg_color text not null default '#f4ecdf',       -- colore di fondo pagina
  menu_bg_color text not null default 'rgba(244,236,223,.72)',  -- sfondo header/menu
  menu_text_color text not null default '#a67f34',     -- colore testo/link nel menu

  -- Font
  font_family text not null default '"Avenir Next","Helvetica Neue",Arial,sans-serif',
  font_custom_url text,                                 -- url di un font caricato (woff2), opzionale
  font_custom_name text,                                 -- nome della @font-face se font_custom_url è impostato

  -- Sfondo: 'pattern' (il motivo a triangoli, personalizzabile), 'solid' (tinta unita),
  -- 'image' (immagine caricata), 'none' (nessun effetto, solo page_bg_color)
  background_mode text not null default 'none' check (background_mode in ('pattern','solid','image','none')),
  background_pattern_color text not null default 'rgba(188,149,78,.23)',
  background_pattern_opacity numeric not null default 0.30,
  background_image_url text,

  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

-- Riga singola di configurazione (id fisso = 1), stesso pattern già in uso per immonova_site_settings.
insert into public.immonova_theme_settings (id) values (1)
on conflict (id) do nothing;

alter table public.immonova_theme_settings enable row level security;

drop policy if exists "theme_settings_select_public" on public.immonova_theme_settings;
create policy "theme_settings_select_public"
  on public.immonova_theme_settings for select
  to anon, authenticated
  using (true);

-- Scrittura riservata a chi ha permesso di scrittura sulla risorsa 'site_settings'
-- (vedi 02_ruoli_permessi.sql per has_permission()). Nel frattempo, se quella
-- funzione non esiste ancora, questa policy fallisce silenziosamente in modo
-- sicuro (nessuno scrive) finché non esegui anche 02_ruoli_permessi.sql.
drop policy if exists "theme_settings_write_admin" on public.immonova_theme_settings;
create policy "theme_settings_write_admin"
  on public.immonova_theme_settings for update
  to authenticated
  using (public.has_permission(auth.uid(), 'site_settings', 'write'))
  with check (public.has_permission(auth.uid(), 'site_settings', 'write'));

select * from public.immonova_theme_settings;
