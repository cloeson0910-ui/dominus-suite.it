-- ============================================================================
-- SITO CLIENTE — tabella che memorizza QUALE licenza usa questo sito.
-- Da eseguire su OGNI progetto Supabase dei clienti (non sul control plane).
-- Esegui dopo 04_correzione_moduli.sql.
-- ============================================================================

create table if not exists public.immonova_license (
  id int primary key default 1 check (id = 1),  -- riga singola, come immonova_site_settings
  license_code text,
  activated_at timestamptz not null default now()
);

alter table public.immonova_license enable row level security;

-- Solo il super_admin può leggere/scrivere il codice licenza.
drop policy if exists "license_super_admin_all" on public.immonova_license;
create policy "license_super_admin_all" on public.immonova_license for all to authenticated
  using (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id = p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ))
  with check (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id = p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ));

select 'Tabella licenza creata.' as esito;
