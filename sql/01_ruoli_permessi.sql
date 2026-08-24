-- ============================================================================
-- PRODOTTO WHITE-LABEL — Ruoli e permessi configurabili
-- Da eseguire SOLO sul progetto Supabase del nuovo prodotto/copia, MAI su
-- quello di immonova.it in produzione (che resta con il sistema attuale,
-- solo admin/collaboratore, invariato).
--
-- Modello:
-- - super_admin: ruolo di sistema, fisso, non modificabile/eliminabile. È chi
--   possiede la piattaforma (tu). Ha SEMPRE tutti i permessi, senza bisogno di
--   righe in immonova_role_permissions.
-- - admin, super_user, user: ruoli "di prodotto", creabili/modificabili dal
--   super_admin. Ognuno ha permessi di lettura/scrittura configurabili per
--   ciascuna sezione (risorsa) della piattaforma: opportunità, investitori,
--   calendario, statistiche, impostazioni sito, utenti, ecc.
-- - profiles.role (testo) resta per compatibilità con il codice esistente;
--   si aggiunge profiles.role_id che punta al ruolo effettivo/configurabile.
-- ============================================================================

-- 1) Tabella ruoli --------------------------------------------------------------
create table if not exists public.immonova_roles (
  id bigint generated always as identity primary key,
  name text not null unique,          -- slug interno, es. 'admin', 'super_user', 'agente_vendite'
  label text not null,                -- nome mostrato, es. 'Amministratore', 'Agente Vendite'
  is_system boolean not null default false,  -- true SOLO per super_admin: non modificabile/eliminabile
  created_at timestamptz not null default now()
);

insert into public.immonova_roles (name, label, is_system) values
  ('super_admin', 'Super Amministratore', true),
  ('admin', 'Amministratore', false),
  ('super_user', 'Super Utente', false),
  ('user', 'Utente', false)
on conflict (name) do nothing;

-- 2) Tabella permessi per ruolo/risorsa -----------------------------------------
-- resource_key identifica una sezione della piattaforma (non una tabella precisa:
-- una sezione può coprire più tabelle collegate, es. 'investors' copre anche
-- investor_categories/investor_areas/investor_seller_properties). L'elenco delle
-- resource_key è deciso lato applicazione (frontend/RLS), qui si registra solo
-- quali un ruolo può leggere e/o scrivere.
create table if not exists public.immonova_role_permissions (
  id bigint generated always as identity primary key,
  role_id bigint not null references public.immonova_roles(id) on delete cascade,
  resource_key text not null,
  can_read boolean not null default false,
  can_write boolean not null default false,
  unique(role_id, resource_key)
);

-- Permessi di default ragionevoli per i tre ruoli di prodotto (il super_admin
-- non ha bisogno di righe: ha sempre accesso completo, vedi has_permission()).
-- admin: accesso completo a tutto.
insert into public.immonova_role_permissions (role_id, resource_key, can_read, can_write)
select r.id, res.key, true, true
from public.immonova_roles r
cross join (values
  ('opportunities'), ('investors'), ('calendar'), ('statistics'),
  ('site_settings'), ('users'), ('broadcast_notifications'), ('communications')
) as res(key)
where r.name = 'admin'
on conflict (role_id, resource_key) do nothing;

-- super_user: può leggere e scrivere sui dati operativi, ma NON su utenti,
-- impostazioni sito o notifiche broadcast (solo lettura lì).
insert into public.immonova_role_permissions (role_id, resource_key, can_read, can_write)
select r.id, v.key, v.can_read, v.can_write
from public.immonova_roles r
cross join (values
  ('opportunities', true, true),
  ('investors', true, true),
  ('calendar', true, true),
  ('statistics', true, false),
  ('site_settings', true, false),
  ('users', false, false),
  ('broadcast_notifications', false, false),
  ('communications', true, true)
) as v(key, can_read, can_write)
where r.name = 'super_user'
on conflict (role_id, resource_key) do nothing;

-- user: solo lettura sui dati operativi, nessun accesso a impostazioni/utenti.
insert into public.immonova_role_permissions (role_id, resource_key, can_read, can_write)
select r.id, v.key, v.can_read, v.can_write
from public.immonova_roles r
cross join (values
  ('opportunities', true, false),
  ('investors', true, false),
  ('calendar', true, false),
  ('statistics', false, false),
  ('site_settings', false, false),
  ('users', false, false),
  ('broadcast_notifications', false, false),
  ('communications', true, false)
) as v(key, can_read, can_write)
where r.name = 'user'
on conflict (role_id, resource_key) do nothing;

-- 3) Collega i profili al ruolo configurabile ------------------------------------
alter table public.profiles
  add column if not exists role_id bigint references public.immonova_roles(id);

-- Migrazione automatica: chi ha già profiles.role='admin' diventa super_admin
-- (sei tu, il proprietario della piattaforma) — puoi poi retrocederlo ad
-- 'admin' di prodotto dalla pagina di gestione ruoli se preferisci.
update public.profiles p
set role_id = (select id from public.immonova_roles where name = 'super_admin')
where p.role = 'admin' and p.role_id is null;

update public.profiles p
set role_id = (select id from public.immonova_roles where name = 'user')
where p.role_id is null;

-- 4) Funzione helper per verificare i permessi -----------------------------------
-- SECURITY DEFINER: bypassa RLS internamente per leggere ruolo/permessi
-- dell'utente chiamante, evitando ricorsioni nelle policy (stessa lezione
-- imparata con il calendario collaboratori in questo progetto).
create or replace function public.has_permission(p_user_id uuid, p_resource_key text, p_action text)
returns boolean
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_role_name text;
  v_allowed boolean;
begin
  select r.name into v_role_name
  from public.profiles p
  join public.immonova_roles r on r.id = p.role_id
  where p.id = p_user_id;

  if v_role_name is null then
    return false;
  end if;

  -- Il super_admin ha sempre accesso completo, senza bisogno di righe permessi.
  if v_role_name = 'super_admin' then
    return true;
  end if;

  select case when p_action = 'write' then rp.can_write else rp.can_read end
  into v_allowed
  from public.immonova_role_permissions rp
  join public.immonova_roles r on r.id = rp.role_id
  where r.name = v_role_name and rp.resource_key = p_resource_key;

  return coalesce(v_allowed, false);
end;
$$;

grant execute on function public.has_permission(uuid, text, text) to authenticated;

-- Funzione di comodo per il frontend: restituisce ruolo + tutti i permessi
-- dell'utente corrente in un'unica chiamata (evita N query separate in ogni
-- pagina admin per capire cosa mostrare/nascondere).
create or replace function public.my_role_and_permissions()
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_role record;
  v_perms jsonb;
begin
  select r.id, r.name, r.label into v_role
  from public.profiles p
  join public.immonova_roles r on r.id = p.role_id
  where p.id = auth.uid();

  if v_role.name is null then
    return jsonb_build_object('role', null, 'permissions', '{}'::jsonb);
  end if;

  if v_role.name = 'super_admin' then
    return jsonb_build_object(
      'role', jsonb_build_object('id', v_role.id, 'name', v_role.name, 'label', v_role.label),
      'is_super_admin', true,
      'permissions', '{}'::jsonb
    );
  end if;

  select coalesce(jsonb_object_agg(rp.resource_key, jsonb_build_object('read', rp.can_read, 'write', rp.can_write)), '{}'::jsonb)
  into v_perms
  from public.immonova_role_permissions rp
  where rp.role_id = v_role.id;

  return jsonb_build_object(
    'role', jsonb_build_object('id', v_role.id, 'name', v_role.name, 'label', v_role.label),
    'is_super_admin', false,
    'permissions', v_perms
  );
end;
$$;

grant execute on function public.my_role_and_permissions() to authenticated;

-- 5) RLS sulle tabelle di ruoli/permessi: solo il super_admin può gestirle -------
alter table public.immonova_roles enable row level security;
alter table public.immonova_role_permissions enable row level security;

drop policy if exists "roles_select" on public.immonova_roles;
create policy "roles_select" on public.immonova_roles for select to authenticated using (true);

drop policy if exists "roles_write_super_admin" on public.immonova_roles;
create policy "roles_write_super_admin" on public.immonova_roles for all to authenticated
  using (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id=p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ))
  with check (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id=p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ));

drop policy if exists "role_permissions_select" on public.immonova_role_permissions;
create policy "role_permissions_select" on public.immonova_role_permissions for select to authenticated using (true);

drop policy if exists "role_permissions_write_super_admin" on public.immonova_role_permissions;
create policy "role_permissions_write_super_admin" on public.immonova_role_permissions for all to authenticated
  using (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id=p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ))
  with check (exists(
    select 1 from public.profiles p join public.immonova_roles r on r.id=p.role_id
    where p.id = auth.uid() and r.name = 'super_admin'
  ));

-- Verifica
select p.email, r.name as ruolo from public.profiles p left join public.immonova_roles r on r.id=p.role_id;
select * from public.immonova_roles order by id;
select r.name, rp.resource_key, rp.can_read, rp.can_write from public.immonova_role_permissions rp join public.immonova_roles r on r.id=rp.role_id order by r.name, rp.resource_key;
