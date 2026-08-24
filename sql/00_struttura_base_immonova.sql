--
-- PostgreSQL database dump
--

\restrict JGYck7yvQcy780buYD8Mjvgp3PziUByob3O1kljOj7NHFEuX8mGRH5sSdOHeREl

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6 (Postgres.app)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if (new.raw_user_meta_data->>'is_public_account') = 'true' then
    return new;
  end if;

  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    'user'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;


--
-- Name: has_capital_partners_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_capital_partners_access() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.is_capital_partners_owner()
  or exists (
    select 1 from public.capital_partners_grants g
    where g.user_id = auth.uid()
  );
$$;


--
-- Name: immonova_ad_drafts_set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_ad_drafts_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: immonova_get_subscription_id(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_get_subscription_id(p_endpoint text) RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select id from public.immonova_push_subscriptions where endpoint = p_endpoint limit 1;
$$;


--
-- Name: immonova_guard_opportunity_edit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_guard_opportunity_edit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  is_admin boolean;
begin
  select (role = 'admin') into is_admin from profiles where id = auth.uid();

  if coalesce(is_admin, false) then
    return new; -- l'admin puo' sempre fare tutto
  end if;

  -- Opportunita' gia' oltre la bozza (in revisione, approvata, rifiutata o
  -- pubblicata): bloccata per chiunque non sia admin, nessuna modifica di
  -- alcun tipo.
  if old.review_status is distinct from 'da_verificare' or old.published = true then
    raise exception 'Questa opportunità è in revisione o pubblicata: solo un amministratore può modificarla.';
  end if;

  -- Ancora in bozza: il collaboratore puo' modificare liberamente i propri
  -- contenuti, ma non puo' toccare direttamente lo stato commerciale, non
  -- puo' pubblicarla da solo, e puo' far avanzare review_status SOLO verso
  -- "da_revisionare" (l'atto di sottoporla in revisione) -- mai direttamente
  -- verso approvato/rifiutato, che restano decisioni dell'admin.
  if new.commercial_status is distinct from old.commercial_status then
    raise exception 'Solo un amministratore può cambiare lo stato commerciale.';
  end if;

  if new.published = true then
    raise exception 'Solo un amministratore può pubblicare un''opportunità.';
  end if;

  if new.review_status is distinct from old.review_status
     and new.review_status is distinct from 'da_verificare'
     and new.review_status is distinct from 'da_revisionare' then
    raise exception 'Solo un amministratore può approvare o rifiutare un''opportunità.';
  end if;

  return new;
end;
$$;


--
-- Name: immonova_handle_new_public_account(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_handle_new_public_account() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if (new.raw_user_meta_data->>'is_public_account') = 'true' then
    insert into public.immonova_public_accounts (id, email, full_name)
    values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;


--
-- Name: immonova_link_subscription_to_account(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_link_subscription_to_account(p_endpoint text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  update public.immonova_push_subscriptions
  set account_id = auth.uid()
  where endpoint = p_endpoint;
$$;


--
-- Name: immonova_set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: immonova_social_posts_set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.immonova_social_posts_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
    and role = 'admin'
  );
$$;


--
-- Name: is_calendar_event_owner_or_admin(bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_calendar_event_owner_or_admin(p_event_id bigint, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.immonova_calendar_events e
    where e.id = p_event_id
      and (
        e.created_by = p_user_id
        or exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'admin')
      )
  );
$$;


--
-- Name: is_calendar_participant(bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_calendar_participant(p_event_id bigint, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.immonova_calendar_event_participants pt
    where pt.event_id = p_event_id and pt.user_id = p_user_id
  );
$$;


--
-- Name: is_capital_partners_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_capital_partners_owner() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(p.email) = lower('claudio.romano@bluewin.ch')
  );
$$;


--
-- Name: nearby_immonova_knowledge_assets(numeric, numeric, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.nearby_immonova_knowledge_assets(p_lat numeric, p_lng numeric, p_radius_km numeric DEFAULT 50, p_category text DEFAULT NULL::text, p_status text DEFAULT 'verified'::text) RETURNS TABLE(id uuid, name text, category text, subtype text, country text, region text, province text, city text, address text, latitude numeric, longitude numeric, distance_km numeric, description text, verification_status text, verified boolean, source text, google_place_id text, prestige_score integer, international_score integer, exclusive_score integer, family_score integer, seasonality_score integer, instagram_score integer, luxury_score integer, tags jsonb, metadata jsonb)
    LANGUAGE sql STABLE
    AS $$
  select
    a.id,
    a.name,
    a.category,
    a.subtype,
    a.country,
    a.region,
    a.province,
    a.city,
    a.address,
    a.latitude,
    a.longitude,
    round(
      (
        st_distance(
          a.geo,
          st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
        ) / 1000
      )::numeric,
      1
    ) as distance_km,
    a.description,
    a.verification_status,
    a.verified,
    a.source,
    a.google_place_id,
    a.prestige_score,
    a.international_score,
    a.exclusive_score,
    a.family_score,
    a.seasonality_score,
    a.instagram_score,
    a.luxury_score,
    a.tags,
    a.metadata
  from public.immonova_knowledge_assets a
  where
    a.active = true
    and (p_category is null or a.category = p_category)
    and (p_status is null or a.verification_status = p_status)
    and st_dwithin(
      a.geo,
      st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  order by distance_km asc;
$$;


--
-- Name: notify_admin_on_app_install(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_admin_on_app_install() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  admin_ids uuid[];
  body_text text;
begin
  select array_agg(id) into admin_ids from public.profiles where role = 'admin';
  if admin_ids is null or array_length(admin_ids, 1) = 0 then
    return new;
  end if;

  body_text := 'Nuova installazione dell''app IMMONOVA';
  if new.country is not null then
    body_text := body_text || ' da ' || new.country;
  end if;

  perform net.http_post(
    url := 'https://bpzzmitmbavcmcasswbu.supabase.co/functions/v1/immonova-calendar-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearersb_secret_79rBG2OZQRHkzoFnrr0aog_Sovmbv8o>'
    ),
    body := jsonb_build_object(
      'user_ids', to_jsonb(admin_ids),
      'title', 'IMMONOVA',
      'body', body_text,
      'url', '/admin/statistics.html'
    )
  );

  return new;
end;
$$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: set_immonova_knowledge_assets_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_immonova_knowledge_assets_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();

  if new.verification_status = 'verified' then
    new.verified = true;
    if new.verified_at is null then
      new.verified_at = now();
    end if;
  else
    new.verified = false;
  end if;

  return new;
end;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: capital_partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capital_partners (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    categoria text DEFAULT ''::text NOT NULL,
    soggetto text NOT NULL,
    soggetto_key text GENERATED ALWAYS AS (lower(TRIM(BOTH FROM soggetto))) STORED,
    hq_area text,
    settori_fit text,
    priorita text,
    sito_ufficiale text,
    email text,
    tipo_contatto text,
    note text,
    fonte_verifica text,
    data_verifica date,
    italia text,
    europa text,
    porti text,
    aeroporti text,
    hospitality text,
    real_estate text,
    infrastructure text,
    stato text DEFAULT 'NON CONTATTATO'::text NOT NULL,
    progetto_compatibile text,
    ultimo_contatto date,
    note_crm text,
    imported_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- Name: capital_partners_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capital_partners_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    granted_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id bigint NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.categories ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: dossier_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dossier_requests (
    id bigint NOT NULL,
    opportunity_id bigint,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    company text,
    role text,
    country text,
    message text,
    privacy_accepted boolean DEFAULT false NOT NULL,
    nda_accepted boolean DEFAULT false NOT NULL,
    status text DEFAULT 'incompleta'::text NOT NULL,
    lead_source text DEFAULT 'website'::text,
    ip_address text,
    user_agent text,
    dossier_sent boolean DEFAULT false NOT NULL,
    dossier_sent_at timestamp with time zone,
    pdf_downloaded boolean DEFAULT false NOT NULL,
    pdf_downloaded_at timestamp with time zone,
    download_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT dossier_requests_status_check CHECK ((status = ANY (ARRAY['incompleta'::text, 'nda_accettato'::text, 'dossier_inviato'::text, 'scaricato'::text])))
);


--
-- Name: dossier_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.dossier_requests ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.dossier_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: event_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event_invitations (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    event_id bigint,
    investor_id bigint,
    channel text DEFAULT 'email'::text,
    invitation_status text DEFAULT 'pending'::text,
    rsvp text DEFAULT 'waiting'::text,
    sent_at timestamp with time zone,
    opened_at timestamp with time zone,
    responded_at timestamp with time zone,
    created_by uuid,
    match_score integer DEFAULT 0,
    match_reasons jsonb DEFAULT '[]'::jsonb,
    selected boolean DEFAULT true,
    email_opt_in boolean DEFAULT false,
    whatsapp_opt_in boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: event_invitations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.event_invitations ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.event_invitations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_access_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_access_logs (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    email text,
    full_name text,
    role text,
    login_at timestamp with time zone DEFAULT now() NOT NULL,
    user_agent text
);


--
-- Name: immonova_access_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_access_logs ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_access_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_ad_drafts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_ad_drafts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    opportunity_id bigint,
    campaign_name text NOT NULL,
    cycle_number integer DEFAULT 1 NOT NULL,
    variant_label text NOT NULL,
    variable_tested text,
    headline text,
    primary_text text,
    description text,
    call_to_action text DEFAULT 'LEARN_MORE'::text,
    destination_url text,
    image_url text,
    image_notes text,
    target_audience_notes text,
    daily_budget_eur numeric(10,2),
    placements text DEFAULT 'automatic'::text,
    status text DEFAULT 'draft'::text NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    launched_at timestamp with time zone,
    meta_ad_id text,
    results_cost_per_dossier numeric(10,2),
    results_ctr numeric(6,4),
    results_notes text,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    target_countries text[] DEFAULT ARRAY['IT'::text] NOT NULL,
    target_age_min integer DEFAULT 18 NOT NULL,
    target_age_max integer,
    target_interests text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT immonova_ad_drafts_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'ready_to_review'::text, 'approved'::text, 'launched'::text, 'paused'::text, 'archived'::text]))),
    CONSTRAINT immonova_ad_drafts_target_age_max_check CHECK (((target_age_max IS NULL) OR ((target_age_max >= 13) AND (target_age_max <= 65)))),
    CONSTRAINT immonova_ad_drafts_target_age_min_check CHECK (((target_age_min >= 13) AND (target_age_min <= 65)))
);


--
-- Name: COLUMN immonova_ad_drafts.target_countries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_ad_drafts.target_countries IS 'Codici Paese ISO a 2 lettere per il targeting geografico (sostituisce il default fisso "solo Italia" usato finora dalla Edge Function)';


--
-- Name: COLUMN immonova_ad_drafts.target_age_min; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_ad_drafts.target_age_min IS 'Età minima del pubblico (13-65)';


--
-- Name: COLUMN immonova_ad_drafts.target_age_max; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_ad_drafts.target_age_max IS 'Età massima del pubblico (13-65), NULL = nessun limite massimo (65+)';


--
-- Name: COLUMN immonova_ad_drafts.target_interests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_ad_drafts.target_interests IS 'Interessi Meta da usare nel targeting, come testo libero da far corrispondere al catalogo interessi di Meta in fase di pubblicazione';


--
-- Name: immonova_app_install_leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_app_install_leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    cognome text NOT NULL,
    email text NOT NULL,
    telefono text,
    privacy_accepted_at timestamp with time zone DEFAULT now() NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_app_installs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_app_installs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    country text,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_calendar_busy_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_calendar_busy_blocks (
    id bigint NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    source text DEFAULT 'icloud'::text NOT NULL,
    synced_at timestamp with time zone DEFAULT now() NOT NULL,
    title text
);


--
-- Name: immonova_calendar_busy_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_calendar_busy_blocks ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_calendar_busy_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_calendar_event_participants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_calendar_event_participants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id bigint NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_calendar_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_calendar_events (
    id bigint NOT NULL,
    event_type text NOT NULL,
    title text NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    notes text,
    opportunity_id bigint,
    created_by uuid,
    icloud_uid text,
    icloud_href text,
    synced_to_icloud boolean DEFAULT false NOT NULL,
    sync_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    address text,
    CONSTRAINT immonova_calendar_events_event_type_check CHECK ((event_type = ANY (ARRAY['telefonata'::text, 'riunione'::text, 'visita_posto'::text])))
);


--
-- Name: immonova_calendar_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_calendar_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_calendar_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_calendar_push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_calendar_push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_contact_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_contact_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    phone text,
    message text NOT NULL,
    language text DEFAULT 'it'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    topic text
);


--
-- Name: immonova_data_dictionary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_data_dictionary (
    id bigint NOT NULL,
    category text NOT NULL,
    field_key text NOT NULL,
    display_name text NOT NULL,
    description text,
    unit text,
    data_type text DEFAULT 'number'::text,
    required boolean DEFAULT false,
    used_for_rating boolean DEFAULT false,
    source_priority text[] DEFAULT '{}'::text[],
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: immonova_data_dictionary_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.immonova_data_dictionary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: immonova_data_dictionary_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.immonova_data_dictionary_id_seq OWNED BY public.immonova_data_dictionary.id;


--
-- Name: immonova_data_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_data_sources (
    id bigint NOT NULL,
    category text NOT NULL,
    country_code text,
    region text,
    province text,
    city text,
    provider_name text NOT NULL,
    endpoint text NOT NULL,
    format text DEFAULT 'json'::text NOT NULL,
    auth_type text DEFAULT 'none'::text NOT NULL,
    method text DEFAULT 'GET'::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    official boolean DEFAULT true NOT NULL,
    source_url text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    provider_type text DEFAULT 'api'::text,
    supports_country boolean DEFAULT true,
    supports_region boolean DEFAULT false,
    supports_province boolean DEFAULT false,
    supports_city boolean DEFAULT false,
    supports_coordinates boolean DEFAULT false,
    supports_year boolean DEFAULT true,
    response_mapping jsonb DEFAULT '{}'::jsonb,
    status text DEFAULT 'active'::text,
    geography_level text DEFAULT 'country'::text,
    geography_name text,
    source_type text DEFAULT 'official'::text,
    document_type text DEFAULT 'html'::text,
    verification_status text DEFAULT 'pending'::text,
    verified_by uuid,
    verified_at timestamp with time zone,
    extraction_enabled boolean DEFAULT true,
    extraction_notes text,
    parser_hint text DEFAULT 'auto'::text
);


--
-- Name: immonova_data_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.immonova_data_sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: immonova_data_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.immonova_data_sources_id_seq OWNED BY public.immonova_data_sources.id;


--
-- Name: immonova_destination_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_destination_photos (
    id bigint NOT NULL,
    country_code text,
    region text,
    province text,
    city text,
    photo_url text NOT NULL,
    credit text,
    caption text,
    active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_destination_photos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_destination_photos ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_destination_photos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_dossier_ads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_dossier_ads (
    id bigint NOT NULL,
    client_name text NOT NULL,
    tagline text,
    contact_line text,
    image_url text NOT NULL,
    size text NOT NULL,
    "position" text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    phone text,
    email text,
    CONSTRAINT immonova_dossier_ads_position_check CHECK (("position" = ANY (ARRAY['after_toc'::text, 'after_financial'::text, 'after_property'::text, 'after_territory'::text, 'after_ecosystem'::text, 'after_evaluation'::text, 'before_closing'::text]))),
    CONSTRAINT immonova_dossier_ads_size_check CHECK ((size = ANY (ARRAY['full'::text, 'half'::text])))
);


--
-- Name: immonova_dossier_ads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_dossier_ads ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_dossier_ads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_event_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_event_media (
    id bigint NOT NULL,
    event_id bigint NOT NULL,
    media_type text DEFAULT 'image'::text NOT NULL,
    file_url text NOT NULL,
    file_name text,
    mime_type text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_event_media_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_event_media ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.immonova_event_media_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_events (
    id bigint NOT NULL,
    title text NOT NULL,
    slug text,
    event_type text DEFAULT 'sold_event'::text NOT NULL,
    status text DEFAULT 'published'::text NOT NULL,
    event_date date,
    event_time text,
    location text,
    venue text,
    address text,
    description text,
    short_description text,
    opportunity_id bigint,
    cover_image text,
    video_url text,
    sold_price text,
    investor_count integer,
    offers_count integer,
    closing_days integer,
    featured boolean DEFAULT false NOT NULL,
    published boolean DEFAULT false NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_events ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.immonova_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_evidence_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_evidence_cache (
    id bigint NOT NULL,
    domain text NOT NULL,
    opportunity_id text,
    country_code text,
    region text,
    province text,
    city text,
    evidence_id text NOT NULL,
    label text,
    value jsonb,
    unit text,
    year integer,
    source_name text,
    source_url text,
    provider_id text,
    retrieved_at timestamp with time zone,
    verified boolean DEFAULT false,
    confidence numeric,
    raw jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: immonova_evidence_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_evidence_cache ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_evidence_cache_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_favorite_opportunities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_favorite_opportunities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subscription_id uuid,
    opportunity_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    account_id uuid
);


--
-- Name: immonova_job_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_job_applications (
    id bigint NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    age integer,
    marital_status text,
    region text,
    country text,
    province text,
    estimated_revenue numeric,
    collaboration_type text NOT NULL,
    message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT immonova_job_applications_collaboration_type_check CHECK ((collaboration_type = ANY (ARRAY['Collaboratore'::text, 'Segnalatore'::text, 'Affiliato'::text, 'Tecnico'::text, 'Legale'::text])))
);


--
-- Name: immonova_job_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_job_applications ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_job_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_knowledge_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_knowledge_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    category text NOT NULL,
    subtype text,
    country text,
    region text,
    province text,
    city text,
    address text,
    latitude numeric NOT NULL,
    longitude numeric NOT NULL,
    geo public.geography(Point,4326) GENERATED ALWAYS AS ((public.st_setsrid(public.st_makepoint((longitude)::double precision, (latitude)::double precision), 4326))::public.geography) STORED,
    description text,
    verification_status text DEFAULT 'candidate'::text NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    source text DEFAULT 'manual'::text,
    source_ref text,
    google_place_id text,
    prestige_score integer,
    international_score integer,
    exclusive_score integer,
    family_score integer,
    seasonality_score integer,
    instagram_score integer,
    luxury_score integer,
    tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    admin_notes text,
    created_by uuid,
    verified_by uuid,
    verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT immonova_knowledge_assets_exclusive_score_check CHECK (((exclusive_score >= 0) AND (exclusive_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_family_score_check CHECK (((family_score >= 0) AND (family_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_instagram_score_check CHECK (((instagram_score >= 0) AND (instagram_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_international_score_check CHECK (((international_score >= 0) AND (international_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_luxury_score_check CHECK (((luxury_score >= 0) AND (luxury_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_prestige_score_check CHECK (((prestige_score >= 0) AND (prestige_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_seasonality_score_check CHECK (((seasonality_score >= 0) AND (seasonality_score <= 100))),
    CONSTRAINT immonova_knowledge_assets_verification_status_check CHECK ((verification_status = ANY (ARRAY['candidate'::text, 'verified'::text, 'rejected'::text, 'archived'::text])))
);


--
-- Name: immonova_manual_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_manual_overrides (
    id bigint NOT NULL,
    opportunity_id bigint,
    country_code text,
    region text,
    province text,
    city text,
    category text NOT NULL,
    field_key text NOT NULL,
    value numeric NOT NULL,
    unit text,
    year integer,
    observation_period text,
    source_note text,
    active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_manual_overrides_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_manual_overrides ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_manual_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_market_comparables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_market_comparables (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    country_code text NOT NULL,
    country text,
    region text,
    province text,
    municipality text,
    city text,
    area_name text,
    geography_level text DEFAULT 'municipality'::text NOT NULL,
    latitude numeric(10,7),
    longitude numeric(10,7),
    radius_km numeric(10,2),
    comparable_type text DEFAULT 'hotel'::text NOT NULL,
    property_name text,
    property_external_id text,
    hotel_stars smallint,
    room_count integer,
    adr numeric(12,2),
    occupancy numeric(7,6),
    revpar numeric(12,2),
    currency character(3) DEFAULT 'EUR'::bpchar NOT NULL,
    observation_year integer NOT NULL,
    observation_period text,
    period_start date,
    period_end date,
    season text,
    source_name text NOT NULL,
    source_url text NOT NULL,
    source_record_url text,
    provider_name text,
    retrieved_at timestamp with time zone DEFAULT now() NOT NULL,
    published_at timestamp with time zone,
    verification_status text DEFAULT 'pending'::text NOT NULL,
    verified boolean GENERATED ALWAYS AS ((verification_status = 'verified'::text)) STORED,
    verified_at timestamp with time zone,
    verified_by uuid,
    confidence numeric(5,4) DEFAULT 0.70 NOT NULL,
    sample_size integer,
    methodology text,
    notes text,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT immonova_market_comparables_adr_check CHECK (((adr IS NULL) OR (adr > (0)::numeric))),
    CONSTRAINT immonova_market_comparables_comparable_type_check CHECK ((comparable_type = ANY (ARRAY['hotel'::text, 'resort'::text, 'bed_and_breakfast'::text, 'aparthotel'::text, 'hostel'::text, 'vacation_rental'::text, 'market_report'::text, 'official_statistic'::text, 'other'::text]))),
    CONSTRAINT immonova_market_comparables_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
    CONSTRAINT immonova_market_comparables_geography_level_check CHECK ((geography_level = ANY (ARRAY['property'::text, 'municipality'::text, 'city'::text, 'province'::text, 'department'::text, 'region'::text, 'country'::text, 'radius'::text, 'market_area'::text]))),
    CONSTRAINT immonova_market_comparables_has_metric CHECK (((adr IS NOT NULL) OR (occupancy IS NOT NULL) OR (revpar IS NOT NULL))),
    CONSTRAINT immonova_market_comparables_hotel_stars_check CHECK (((hotel_stars >= 1) AND (hotel_stars <= 5))),
    CONSTRAINT immonova_market_comparables_observation_year_check CHECK (((observation_year >= 1900) AND (observation_year <= 2200))),
    CONSTRAINT immonova_market_comparables_occupancy_check CHECK (((occupancy IS NULL) OR ((occupancy >= (0)::numeric) AND (occupancy <= (1)::numeric)))),
    CONSTRAINT immonova_market_comparables_period_valid CHECK (((period_start IS NULL) OR (period_end IS NULL) OR (period_end >= period_start))),
    CONSTRAINT immonova_market_comparables_revpar_check CHECK (((revpar IS NULL) OR (revpar >= (0)::numeric))),
    CONSTRAINT immonova_market_comparables_room_count_check CHECK (((room_count IS NULL) OR (room_count >= 0))),
    CONSTRAINT immonova_market_comparables_sample_size_check CHECK (((sample_size IS NULL) OR (sample_size >= 0))),
    CONSTRAINT immonova_market_comparables_season_check CHECK (((season IS NULL) OR (season = ANY (ARRAY['annual'::text, 'high'::text, 'shoulder'::text, 'low'::text, 'monthly'::text, 'daily'::text, 'other'::text])))),
    CONSTRAINT immonova_market_comparables_verification_status_check CHECK ((verification_status = ANY (ARRAY['pending'::text, 'verified'::text, 'rejected'::text, 'expired'::text])))
);


--
-- Name: TABLE immonova_market_comparables; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.immonova_market_comparables IS 'Universal, source-backed ADR/occupancy/RevPAR comparables. Never insert inferred or unverified values as verified.';


--
-- Name: immonova_market_intelligence_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_market_intelligence_cache (
    id bigint NOT NULL,
    cache_key text NOT NULL,
    country_code text,
    region text,
    province text,
    city text,
    payload jsonb NOT NULL,
    fetched_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_market_intelligence_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_market_intelligence_cache ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_market_intelligence_cache_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_opportunity_views; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_opportunity_views (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    opportunity_id bigint NOT NULL,
    country text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: immonova_property_valuations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_property_valuations (
    id bigint NOT NULL,
    seller_first_name text NOT NULL,
    seller_last_name text NOT NULL,
    seller_phone text,
    seller_email text,
    property_title text,
    category text,
    address text,
    municipality text,
    province text,
    region text,
    country text DEFAULT 'Italia'::text,
    latitude numeric,
    longitude numeric,
    internal_size numeric,
    land_size numeric,
    bedrooms integer,
    bathrooms integer,
    construction_year integer,
    energy_class text,
    property_condition text,
    cadastral_municipality text,
    cadastral_category text,
    cadastral_income numeric,
    cadastral_surface numeric,
    cadastral_sheet text,
    cadastral_parcel text,
    cadastral_subalterno text,
    notes text,
    estimated_value_min numeric,
    estimated_value_max numeric,
    estimated_value_per_sqm numeric,
    comparables_snapshot jsonb,
    valuation_generated_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    has_pool boolean DEFAULT false NOT NULL,
    has_garden boolean DEFAULT false NOT NULL,
    garden_sqm numeric,
    has_garage boolean DEFAULT false NOT NULL,
    garage_sqm numeric,
    has_parking_spot boolean DEFAULT false NOT NULL,
    has_terrace boolean DEFAULT false NOT NULL,
    has_balcony boolean DEFAULT false NOT NULL,
    has_sea_view boolean DEFAULT false NOT NULL,
    has_historic_center boolean DEFAULT false NOT NULL,
    has_air_conditioning boolean DEFAULT false NOT NULL,
    has_elevator boolean DEFAULT false NOT NULL,
    has_fireplace boolean DEFAULT false NOT NULL,
    has_beachfront boolean DEFAULT false NOT NULL,
    has_photovoltaic boolean DEFAULT false NOT NULL,
    photovoltaic_kw numeric,
    has_car_charger boolean DEFAULT false NOT NULL,
    has_solar_thermal boolean DEFAULT false NOT NULL,
    has_storage_battery boolean DEFAULT false NOT NULL,
    has_artesian_well boolean DEFAULT false NOT NULL,
    has_heating_system boolean DEFAULT false NOT NULL,
    has_habitability boolean DEFAULT false NOT NULL,
    omi_zone text,
    omi_min_per_sqm numeric,
    omi_max_per_sqm numeric,
    omi_state text,
    prima_casa boolean DEFAULT false NOT NULL,
    valuation_immonova_min numeric,
    valuation_immonova_max numeric,
    valuation_omi_min numeric,
    valuation_omi_max numeric,
    valuation_catastale numeric,
    cadastral_value numeric,
    is_rented boolean DEFAULT false NOT NULL,
    current_annual_rent numeric,
    accessory_size numeric,
    valuation_comparativo_min numeric,
    valuation_comparativo_max numeric,
    valuation_reddituale_min numeric,
    valuation_reddituale_max numeric,
    suggested_listing_price numeric,
    ai_narrative jsonb,
    ai_comparables jsonb,
    yield_min_manual numeric,
    yield_max_manual numeric,
    cadastral_is_prima_casa boolean DEFAULT false NOT NULL,
    cadastral_multiplier numeric,
    price_index_trend jsonb
);


--
-- Name: COLUMN immonova_property_valuations.cadastral_value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_property_valuations.cadastral_value IS 'Valore catastale calcolato: rendita catastale rivalutata del 5% moltiplicata per il coefficiente della categoria catastale (D.L. 262/2006, art. 2 c. 45) — dato fiscale, distinto dal valore di mercato';


--
-- Name: COLUMN immonova_property_valuations.cadastral_is_prima_casa; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_property_valuations.cadastral_is_prima_casa IS 'Se true, applica il moltiplicatore catastale agevolato "prima casa" (110 invece di 120) per le categorie A escluso A/10 e C escluso C/1';


--
-- Name: COLUMN immonova_property_valuations.cadastral_multiplier; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_property_valuations.cadastral_multiplier IS 'Moltiplicatore catastale applicato nel calcolo di cadastral_value, salvato per trasparenza/tracciabilità nel documento finale';


--
-- Name: COLUMN immonova_property_valuations.price_index_trend; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_property_valuations.price_index_trend IS 'Andamento storico indice prezzi immobiliari (Eurostat prc_hpi_a, copertura a livello paese) — usato per il grafico di trend 5/10 anni nella relazione di valutazione, null se il paese non è coperto dal dataset';


--
-- Name: immonova_property_valuations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_property_valuations ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_property_valuations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_provider_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_provider_mapping (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    provider_field text NOT NULL,
    dictionary_field text NOT NULL,
    transform text,
    required boolean DEFAULT true,
    notes text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: immonova_provider_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.immonova_provider_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: immonova_provider_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.immonova_provider_mapping_id_seq OWNED BY public.immonova_provider_mapping.id;


--
-- Name: immonova_provider_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_provider_registry (
    id text NOT NULL,
    name text NOT NULL,
    domain text NOT NULL,
    provider_type text DEFAULT 'http_json'::text NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    official boolean DEFAULT true NOT NULL,
    country_code text,
    country text,
    region text,
    province text,
    city text,
    geography_level text,
    url_template text,
    method text DEFAULT 'GET'::text,
    headers jsonb DEFAULT '{}'::jsonb,
    body_template jsonb,
    response_format text DEFAULT 'json'::text,
    items_path text,
    mapping jsonb DEFAULT '{}'::jsonb,
    source_name text,
    source_url text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: immonova_public_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_public_accounts (
    id uuid NOT NULL,
    email text NOT NULL,
    full_name text,
    notification_channel text DEFAULT 'push'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    phone text,
    CONSTRAINT immonova_public_accounts_notification_channel_check CHECK ((notification_channel = ANY (ARRAY['push'::text, 'email'::text])))
);


--
-- Name: immonova_push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    consent_at timestamp with time zone DEFAULT now() NOT NULL,
    user_agent text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    account_id uuid
);


--
-- Name: immonova_search_mandates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_search_mandates (
    id bigint NOT NULL,
    client_name text NOT NULL,
    client_phone text,
    client_email text,
    category text,
    location_areas text,
    budget_min numeric,
    budget_max numeric,
    sqm_min numeric,
    sqm_max numeric,
    bedrooms_min integer,
    bathrooms_min integer,
    wants_garden boolean DEFAULT false NOT NULL,
    wants_pool boolean DEFAULT false NOT NULL,
    wants_garage boolean DEFAULT false NOT NULL,
    wants_sea_view boolean DEFAULT false NOT NULL,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    bedrooms_max integer,
    bathrooms_max integer,
    wants_parking_spot boolean DEFAULT false NOT NULL,
    wants_terrace boolean DEFAULT false NOT NULL,
    wants_balcony boolean DEFAULT false NOT NULL,
    wants_historic_center boolean DEFAULT false NOT NULL,
    wants_air_conditioning boolean DEFAULT false NOT NULL,
    wants_elevator boolean DEFAULT false NOT NULL,
    wants_fireplace boolean DEFAULT false NOT NULL,
    wants_beachfront boolean DEFAULT false NOT NULL,
    wants_photovoltaic boolean DEFAULT false NOT NULL,
    wants_car_charger boolean DEFAULT false NOT NULL,
    wants_solar_thermal boolean DEFAULT false NOT NULL,
    wants_storage_battery boolean DEFAULT false NOT NULL,
    wants_artesian_well boolean DEFAULT false NOT NULL,
    wants_heating_system boolean DEFAULT false NOT NULL,
    wants_habitability boolean DEFAULT false NOT NULL
);


--
-- Name: immonova_search_mandates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.immonova_search_mandates ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.immonova_search_mandates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: immonova_social_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.immonova_social_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    opportunity_id bigint,
    caption text,
    image_url text,
    link_url text,
    post_type text DEFAULT 'feed'::text NOT NULL,
    publish_to_facebook boolean DEFAULT true NOT NULL,
    publish_to_instagram boolean DEFAULT true NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    published_at timestamp with time zone,
    facebook_post_id text,
    instagram_post_id text,
    publish_error text,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    publish_to_linkedin boolean DEFAULT false NOT NULL,
    linkedin_post_id text,
    text_font text DEFAULT 'montserrat'::text NOT NULL,
    text_color text DEFAULT '#d6ab4b'::text NOT NULL,
    text_bold boolean DEFAULT true NOT NULL,
    text_underline boolean DEFAULT false NOT NULL,
    image_filter text DEFAULT 'none'::text NOT NULL,
    story_sticker text DEFAULT 'none'::text NOT NULL,
    story_sticker_text text,
    hashtags text,
    media_type text DEFAULT 'image'::text NOT NULL,
    video_url text,
    carousel_image_urls text[] DEFAULT '{}'::text[] NOT NULL,
    scheduled_publish_at timestamp with time zone,
    CONSTRAINT immonova_social_posts_post_type_check CHECK ((post_type = ANY (ARRAY['feed'::text, 'story'::text]))),
    CONSTRAINT immonova_social_posts_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'ready_to_review'::text, 'approved'::text, 'scheduled'::text, 'published'::text, 'archived'::text])))
);


--
-- Name: COLUMN immonova_social_posts.publish_to_linkedin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.publish_to_linkedin IS 'Se true, il post va pubblicato anche sulla Pagina aziendale LinkedIn di IMMONOVA';


--
-- Name: COLUMN immonova_social_posts.linkedin_post_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.linkedin_post_id IS 'URN del post creato su LinkedIn (es. urn:li:share:12345), restituito dalla Community Management API dopo la pubblicazione';


--
-- Name: COLUMN immonova_social_posts.text_font; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.text_font IS 'Font usato per il testo scritto sopra l''immagine nelle Storie Instagram';


--
-- Name: COLUMN immonova_social_posts.text_color; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.text_color IS 'Colore esadecimale (#RRGGBB) del testo sovrapposto sulle Storie';


--
-- Name: COLUMN immonova_social_posts.text_bold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.text_bold IS 'Se true, il testo sovrapposto sulle Storie è in grassetto';


--
-- Name: COLUMN immonova_social_posts.text_underline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.text_underline IS 'Se true, il testo sovrapposto sulle Storie è sottolineato';


--
-- Name: COLUMN immonova_social_posts.image_filter; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.image_filter IS 'Effetto applicato all''immagine prima della pubblicazione (bianco e nero, seppia, caldo, freddo, vivace, nessuno)';


--
-- Name: COLUMN immonova_social_posts.story_sticker; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.story_sticker IS 'Sticker grafico originale (disegnato da noi, non copia di Instagram) sovrapposto alla Storia: none, cta_arrow (freccia + "Scopri di più"), new_badge (badge "Nuovo annuncio"), price_tag (badge prezzo)';


--
-- Name: COLUMN immonova_social_posts.story_sticker_text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.story_sticker_text IS 'Testo personalizzato per new_badge/price_tag, opzionale';


--
-- Name: COLUMN immonova_social_posts.hashtags; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.hashtags IS 'Hashtag (es. "#immobililusso #realestate #salento"), separati da spazio o a capo — aggiunti automaticamente in fondo alla caption solo per i post nel feed, non per le Storie';


--
-- Name: COLUMN immonova_social_posts.media_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.media_type IS 'Formato del post: image (foto singola), video (incluso Reels su Instagram), carousel (slideshow/più immagini in un unico post)';


--
-- Name: COLUMN immonova_social_posts.video_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.video_url IS 'URL pubblico del file video, usato quando media_type = video (Facebook: post video normale; Instagram: Reels se post_type=feed, video-storia se post_type=story)';


--
-- Name: COLUMN immonova_social_posts.carousel_image_urls; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.immonova_social_posts.carousel_image_urls IS 'Elenco ordinato di URL immagine per un post carosello/slideshow (media_type = carousel) — non supportato per le Storie';


--
-- Name: inquiries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inquiries (
    id bigint NOT NULL,
    opportunity_id bigint,
    name text NOT NULL,
    email text NOT NULL,
    phone text,
    message text,
    created_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'pending'::text
);


--
-- Name: inquiries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.inquiries ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.inquiries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: investor_areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investor_areas (
    id bigint NOT NULL,
    investor_id bigint,
    area text NOT NULL
);


--
-- Name: investor_areas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.investor_areas ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.investor_areas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: investor_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investor_categories (
    id bigint NOT NULL,
    investor_id bigint,
    category text NOT NULL
);


--
-- Name: investor_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.investor_categories ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.investor_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: investor_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investor_requests (
    id bigint NOT NULL,
    opportunity_id bigint,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    country text NOT NULL,
    preferred_language text NOT NULL,
    company text,
    budget_range text,
    message text,
    nda_accepted boolean DEFAULT false NOT NULL,
    nda_accepted_at timestamp with time zone,
    nda_text_version text DEFAULT 'IMMONOVA_NDA_V1'::text,
    request_completed boolean DEFAULT false NOT NULL,
    completion_status text DEFAULT 'incomplete'::text NOT NULL,
    user_agent text,
    source_page text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    approved boolean DEFAULT false NOT NULL,
    approved_at timestamp with time zone,
    approved_by uuid,
    dossier_sent boolean DEFAULT false NOT NULL,
    dossier_sent_at timestamp with time zone,
    internal_note text,
    opportunity_title text,
    full_name text,
    investor_type text,
    privacy_accepted boolean DEFAULT false,
    privacy_accepted_at timestamp with time zone,
    status text DEFAULT 'pending'::text,
    request_status text DEFAULT 'pending'::text,
    rejected_at timestamp with time zone,
    rejected_by uuid,
    admin_note text,
    dossier_pdf_url text,
    reminder_day1_sent_at timestamp with time zone,
    reminder_day15_sent_at timestamp with time zone,
    CONSTRAINT investor_requests_completion_status_check CHECK ((completion_status = ANY (ARRAY['incomplete'::text, 'nda_not_accepted'::text, 'completed'::text, 'pending_review'::text, 'approved'::text, 'dossier_sent'::text, 'contacted'::text, 'qualified'::text, 'rejected'::text]))),
    CONSTRAINT investor_requests_preferred_language_check CHECK ((preferred_language = ANY (ARRAY['it'::text, 'en'::text, 'fr'::text, 'de'::text, 'es'::text, 'ar'::text, 'ru'::text, 'zh'::text])))
);


--
-- Name: investor_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.investor_requests ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.investor_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: investor_seller_properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investor_seller_properties (
    id bigint NOT NULL,
    investor_id bigint NOT NULL,
    opportunity_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE investor_seller_properties; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.investor_seller_properties IS 'Collega un cliente-venditore (investors) a uno o più immobili di sua proprietà (opportunities)';


--
-- Name: investor_seller_properties_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.investor_seller_properties ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.investor_seller_properties_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: investors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investors (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    first_name text NOT NULL,
    last_name text NOT NULL,
    company text,
    email text NOT NULL,
    phone text,
    whatsapp text,
    country text,
    city text,
    preferred_language text DEFAULT 'it'::text,
    budget_min numeric,
    budget_max numeric,
    investor_type text DEFAULT 'private'::text,
    status text DEFAULT 'active'::text,
    email_opt_in boolean DEFAULT true,
    whatsapp_opt_in boolean DEFAULT false,
    notes text,
    created_by uuid,
    is_investor boolean DEFAULT true NOT NULL,
    is_seller boolean DEFAULT false NOT NULL,
    seller_status text,
    CONSTRAINT investors_seller_status_check CHECK (((seller_status IS NULL) OR (seller_status = ANY (ARRAY['da_contattare'::text, 'in_trattativa'::text, 'mandato_firmato'::text, 'venduto'::text]))))
);


--
-- Name: COLUMN investors.is_investor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.investors.is_investor IS 'true se il cliente è (anche) un investitore';


--
-- Name: COLUMN investors.is_seller; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.investors.is_seller IS 'true se il cliente è (anche) un venditore';


--
-- Name: COLUMN investors.seller_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.investors.seller_status IS 'stato della trattativa lato venditore: da_contattare, in_trattativa, mandato_firmato, venduto';


--
-- Name: investors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.investors ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.investors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: nda_acceptances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nda_acceptances (
    id bigint NOT NULL,
    dossier_request_id bigint,
    opportunity_id bigint,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text NOT NULL,
    phone text NOT NULL,
    company text,
    role text,
    country text,
    nda_version text DEFAULT 'IMMONOVA_NDA_V1'::text NOT NULL,
    nda_text_snapshot text NOT NULL,
    accepted_at timestamp with time zone DEFAULT now(),
    ip_address text,
    user_agent text
);


--
-- Name: nda_acceptances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.nda_acceptances ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.nda_acceptances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opportunities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunities (
    id bigint NOT NULL,
    title text NOT NULL,
    slug text NOT NULL,
    category text NOT NULL,
    short_description text,
    full_description text,
    location text,
    price text,
    cover_image text,
    published boolean DEFAULT false,
    featured boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    bedrooms integer,
    bathrooms integer,
    internal_size integer,
    land_size integer,
    investment_type text,
    latitude numeric,
    longitude numeric,
    updated_at timestamp with time zone DEFAULT now(),
    gallery_images jsonb DEFAULT '[]'::jsonb,
    user_id uuid,
    review_status text DEFAULT 'da_verificare'::text NOT NULL,
    admin_note text,
    reviewed_at timestamp with time zone,
    reviewed_by uuid,
    construction_year integer,
    energy_class text,
    property_condition text,
    distance_to_sea_km numeric,
    distance_to_airport_km numeric,
    nearest_airport text,
    municipality text,
    province text,
    region text,
    location_summary text,
    tourism_summary text,
    market_summary text,
    ai_short_rental_summary text,
    ai_generated_description boolean DEFAULT false NOT NULL,
    ai_generated_at timestamp with time zone,
    preliminary_investment_score numeric,
    renovation_required boolean DEFAULT false NOT NULL,
    renovation_style text,
    renovation_images jsonb DEFAULT '[]'::jsonb,
    renovation_notes text,
    renovation_level text,
    renovation_area_sqm numeric,
    renovation_cost_min numeric,
    renovation_cost_max numeric,
    renovation_cost_avg numeric,
    post_renovation_value_min numeric,
    post_renovation_value_max numeric,
    address text,
    locality text,
    postal_code text,
    formatted_address text,
    commercial_status text DEFAULT 'available'::text,
    sold_at timestamp with time zone,
    sold_event_id bigint,
    reserved_at timestamp with time zone,
    withdrawn_at timestamp with time zone,
    show_price_public boolean DEFAULT true,
    collaborators_notified_at timestamp with time zone,
    owner_id uuid,
    has_pool boolean DEFAULT false NOT NULL,
    has_garden boolean DEFAULT false NOT NULL,
    has_garage boolean DEFAULT false NOT NULL,
    has_parking_spot boolean DEFAULT false NOT NULL,
    has_terrace boolean DEFAULT false NOT NULL,
    has_balcony boolean DEFAULT false NOT NULL,
    has_sea_view boolean DEFAULT false NOT NULL,
    has_historic_center boolean DEFAULT false NOT NULL,
    has_air_conditioning boolean DEFAULT false NOT NULL,
    has_elevator boolean DEFAULT false NOT NULL,
    has_fireplace boolean DEFAULT false NOT NULL,
    has_beachfront boolean DEFAULT false NOT NULL,
    has_photovoltaic boolean DEFAULT false NOT NULL,
    photovoltaic_kw numeric,
    has_car_charger boolean DEFAULT false NOT NULL,
    has_solar_thermal boolean DEFAULT false NOT NULL,
    has_storage_battery boolean DEFAULT false NOT NULL,
    has_artesian_well boolean DEFAULT false NOT NULL,
    has_heating_system boolean DEFAULT false NOT NULL,
    has_habitability boolean DEFAULT false NOT NULL,
    room_inventory jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT opportunities_renovation_style_check CHECK (((renovation_style IS NULL) OR (renovation_style = ANY (ARRAY['normale'::text, 'conservativo'::text, 'lusso'::text])))),
    CONSTRAINT opportunities_review_status_check CHECK ((review_status = ANY (ARRAY['da_verificare'::text, 'da_revisionare'::text, 'approvato'::text, 'rifiutato'::text])))
);


--
-- Name: COLUMN opportunities.room_inventory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.opportunities.room_inventory IS 'Composizione camere/alloggi per corpo di fabbrica (array di edifici, ognuno con nome e tipologie di camere con relativo conteggio) — usato per il calcolo unità nell''ADR, con fallback sul campo bedrooms se vuoto';


--
-- Name: opportunities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opportunities ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opportunities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opportunity_contact_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunity_contact_history (
    id bigint NOT NULL,
    opportunity_id bigint,
    investor_id bigint,
    list_id bigint,
    channel text NOT NULL,
    status text DEFAULT 'sent'::text,
    message_type text DEFAULT 'opportunity_preview'::text,
    subject text,
    email text,
    phone text,
    match_score integer DEFAULT 0,
    match_reasons jsonb DEFAULT '[]'::jsonb,
    include_dossier boolean DEFAULT false,
    dossier_sent boolean DEFAULT false,
    opened_at timestamp with time zone,
    clicked_at timestamp with time zone,
    requested_info_at timestamp with time zone,
    dossier_sent_at timestamp with time zone,
    offer_received_at timestamp with time zone,
    error_message text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: opportunity_contact_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_contact_history ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opportunity_contact_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opportunity_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunity_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    opportunity_id bigint NOT NULL,
    document_type text NOT NULL,
    file_name text NOT NULL,
    file_path text NOT NULL,
    file_url text NOT NULL,
    mime_type text,
    file_size bigint,
    uploaded_by uuid DEFAULT auth.uid(),
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    include_in_dossier boolean DEFAULT false NOT NULL,
    CONSTRAINT opportunity_documents_type_check CHECK ((document_type = ANY (ARRAY['owner_identity'::text, 'owner_tax_code'::text, 'deed_of_origin'::text, 'cadastral_report'::text, 'cadastral_plan'::text, 'ape'::text, 'urban_planning'::text, 'technical_conformity'::text, 'habitability'::text, 'systems_certifications'::text])))
);


--
-- Name: opportunity_document_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.opportunity_document_summary AS
 WITH required AS (
         SELECT unnest(ARRAY['owner_identity'::text, 'owner_tax_code'::text, 'deed_of_origin'::text, 'cadastral_report'::text, 'cadastral_plan'::text, 'ape'::text, 'urban_planning'::text, 'technical_conformity'::text, 'habitability'::text, 'systems_certifications'::text]) AS document_type
        ), counts AS (
         SELECT o.id AS opportunity_id,
            count(DISTINCT od.document_type) FILTER (WHERE (od.document_type IN ( SELECT required.document_type
                   FROM required))) AS loaded_documents,
            count(od.id) FILTER (WHERE (od.document_type IN ( SELECT required.document_type
                   FROM required))) AS total_uploaded_files
           FROM (public.opportunities o
             LEFT JOIN public.opportunity_documents od ON ((od.opportunity_id = o.id)))
          GROUP BY o.id
        )
 SELECT opportunity_id,
    loaded_documents,
    10 AS required_documents,
    (10 - loaded_documents) AS missing_documents,
    total_uploaded_files
   FROM counts;


--
-- Name: opportunity_investor_list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunity_investor_list_items (
    id bigint NOT NULL,
    list_id bigint,
    investor_id bigint,
    match_score integer DEFAULT 0,
    match_reasons jsonb DEFAULT '[]'::jsonb,
    selected boolean DEFAULT true,
    email_opt_in boolean DEFAULT false,
    whatsapp_opt_in boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: opportunity_investor_list_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_investor_list_items ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opportunity_investor_list_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opportunity_investor_lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunity_investor_lists (
    id bigint NOT NULL,
    opportunity_id bigint,
    name text NOT NULL,
    list_type text DEFAULT 'ad_momentum'::text,
    status text DEFAULT 'draft'::text,
    notes text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: opportunity_investor_lists_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_investor_lists ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opportunity_investor_lists_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opportunity_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunity_reports (
    id bigint NOT NULL,
    opportunity_id bigint,
    executive_summary text,
    property_description text,
    location_attractiveness text,
    real_estate_market_past text,
    real_estate_market_forecast text,
    revaluation_forecast_5y text,
    short_rental_analysis text,
    tourism_last_5y text,
    tourism_forecast_5y text,
    risk_analysis text,
    break_even_analysis text,
    swot_analysis text,
    investment_score numeric,
    estimated_roi numeric,
    estimated_revaluation numeric,
    pdf_url text,
    generated_by uuid,
    generated_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    report_json jsonb,
    tourism_data jsonb,
    real_estate_data jsonb,
    short_rental_data jsonb,
    forecast_data jsonb,
    risk_data jsonb,
    break_even_years numeric,
    annual_revenue_estimate numeric,
    annual_cost_estimate numeric,
    net_annual_income_estimate numeric,
    adr_estimate numeric,
    occupancy_rate_estimate numeric,
    revpar_estimate numeric,
    market_growth_5y_percent numeric,
    tourism_growth_5y_percent numeric,
    projected_value_5y numeric,
    projected_revaluation_5y_percent numeric,
    analyst_note text,
    analyst_overridden boolean DEFAULT false,
    analyst_updated_at timestamp with time zone,
    renovation_required boolean DEFAULT false NOT NULL,
    renovation_scenarios jsonb DEFAULT '{}'::jsonb,
    renovation_selected_style text,
    renovation_cost_min numeric,
    renovation_cost_max numeric,
    renovation_cost_avg numeric,
    total_investment_min numeric,
    total_investment_max numeric,
    total_investment_avg numeric,
    renovation_visual_analysis text,
    renovation_renderings jsonb DEFAULT '[]'::jsonb,
    research_sources jsonb,
    data_quality_score numeric,
    investment_rating text,
    scoring_notes jsonb,
    research_mode text DEFAULT 'model'::text,
    research_warnings jsonb,
    research_missing_fields jsonb,
    destination_analysis jsonb,
    translated_languages jsonb DEFAULT '["it"]'::jsonb NOT NULL,
    CONSTRAINT opportunity_reports_renovation_selected_style_check CHECK (((renovation_selected_style IS NULL) OR (renovation_selected_style = ANY (ARRAY['normale'::text, 'conservativo'::text, 'lusso'::text]))))
);


--
-- Name: opportunity_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_reports ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opportunity_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: opportunity_timeline; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunity_timeline (
    id bigint NOT NULL,
    opportunity_id bigint NOT NULL,
    event_id bigint,
    timeline_type text NOT NULL,
    title text NOT NULL,
    description text,
    visibility text DEFAULT 'public'::text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    created_by_name text
);


--
-- Name: opportunity_timeline_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_timeline ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.opportunity_timeline_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text,
    full_name text,
    role text DEFAULT 'user'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    phone text,
    professional_role text DEFAULT 'collaboratore'::text,
    active boolean DEFAULT true,
    preferred_language text DEFAULT 'it'::text,
    language text DEFAULT 'it'::text NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL,
    CONSTRAINT profiles_professional_role_check CHECK ((professional_role = ANY (ARRAY['collaboratore'::text, 'segnalatore'::text, 'affiliato'::text, 'tecnico'::text, 'legale'::text])))
);


--
-- Name: renovation_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.renovation_images (
    id bigint NOT NULL,
    opportunity_id bigint NOT NULL,
    room_type text NOT NULL,
    original_image text NOT NULL,
    render_conservative text,
    render_standard text,
    render_luxury text,
    created_at timestamp with time zone DEFAULT now(),
    ai_detected boolean DEFAULT false
);


--
-- Name: renovation_images_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.renovation_images ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.renovation_images_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: renovation_renders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.renovation_renders (
    id bigint NOT NULL,
    opportunity_id bigint NOT NULL,
    source_image_url text NOT NULL,
    style text NOT NULL,
    room_type text,
    generated_image_url text,
    estimated_cost_min numeric,
    estimated_cost_max numeric,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: renovation_renders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.renovation_renders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: renovation_renders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.renovation_renders_id_seq OWNED BY public.renovation_renders.id;


--
-- Name: site_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site_settings (
    id integer DEFAULT 1 NOT NULL,
    instagram_url text,
    facebook_url text,
    linkedin_url text,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT single_row CHECK ((id = 1))
);


--
-- Name: immonova_data_dictionary id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_data_dictionary ALTER COLUMN id SET DEFAULT nextval('public.immonova_data_dictionary_id_seq'::regclass);


--
-- Name: immonova_data_sources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_data_sources ALTER COLUMN id SET DEFAULT nextval('public.immonova_data_sources_id_seq'::regclass);


--
-- Name: immonova_provider_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_provider_mapping ALTER COLUMN id SET DEFAULT nextval('public.immonova_provider_mapping_id_seq'::regclass);


--
-- Name: renovation_renders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renovation_renders ALTER COLUMN id SET DEFAULT nextval('public.renovation_renders_id_seq'::regclass);


--
-- Name: capital_partners_grants capital_partners_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capital_partners_grants
    ADD CONSTRAINT capital_partners_grants_pkey PRIMARY KEY (id);


--
-- Name: capital_partners_grants capital_partners_grants_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capital_partners_grants
    ADD CONSTRAINT capital_partners_grants_user_id_key UNIQUE (user_id);


--
-- Name: capital_partners capital_partners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capital_partners
    ADD CONSTRAINT capital_partners_pkey PRIMARY KEY (id);


--
-- Name: categories categories_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: dossier_requests dossier_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dossier_requests
    ADD CONSTRAINT dossier_requests_pkey PRIMARY KEY (id);


--
-- Name: event_invitations event_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invitations
    ADD CONSTRAINT event_invitations_pkey PRIMARY KEY (id);


--
-- Name: immonova_access_logs immonova_access_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_access_logs
    ADD CONSTRAINT immonova_access_logs_pkey PRIMARY KEY (id);


--
-- Name: immonova_ad_drafts immonova_ad_drafts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_ad_drafts
    ADD CONSTRAINT immonova_ad_drafts_pkey PRIMARY KEY (id);


--
-- Name: immonova_app_install_leads immonova_app_install_leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_app_install_leads
    ADD CONSTRAINT immonova_app_install_leads_pkey PRIMARY KEY (id);


--
-- Name: immonova_app_installs immonova_app_installs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_app_installs
    ADD CONSTRAINT immonova_app_installs_pkey PRIMARY KEY (id);


--
-- Name: immonova_calendar_busy_blocks immonova_calendar_busy_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_busy_blocks
    ADD CONSTRAINT immonova_calendar_busy_blocks_pkey PRIMARY KEY (id);


--
-- Name: immonova_calendar_event_participants immonova_calendar_event_participants_event_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_event_participants
    ADD CONSTRAINT immonova_calendar_event_participants_event_id_user_id_key UNIQUE (event_id, user_id);


--
-- Name: immonova_calendar_event_participants immonova_calendar_event_participants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_event_participants
    ADD CONSTRAINT immonova_calendar_event_participants_pkey PRIMARY KEY (id);


--
-- Name: immonova_calendar_events immonova_calendar_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_events
    ADD CONSTRAINT immonova_calendar_events_pkey PRIMARY KEY (id);


--
-- Name: immonova_calendar_push_subscriptions immonova_calendar_push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_push_subscriptions
    ADD CONSTRAINT immonova_calendar_push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: immonova_calendar_push_subscriptions immonova_calendar_push_subscriptions_user_id_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_push_subscriptions
    ADD CONSTRAINT immonova_calendar_push_subscriptions_user_id_endpoint_key UNIQUE (user_id, endpoint);


--
-- Name: immonova_contact_requests immonova_contact_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_contact_requests
    ADD CONSTRAINT immonova_contact_requests_pkey PRIMARY KEY (id);


--
-- Name: immonova_data_dictionary immonova_data_dictionary_field_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_data_dictionary
    ADD CONSTRAINT immonova_data_dictionary_field_key_key UNIQUE (field_key);


--
-- Name: immonova_data_dictionary immonova_data_dictionary_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_data_dictionary
    ADD CONSTRAINT immonova_data_dictionary_pkey PRIMARY KEY (id);


--
-- Name: immonova_data_sources immonova_data_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_data_sources
    ADD CONSTRAINT immonova_data_sources_pkey PRIMARY KEY (id);


--
-- Name: immonova_destination_photos immonova_destination_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_destination_photos
    ADD CONSTRAINT immonova_destination_photos_pkey PRIMARY KEY (id);


--
-- Name: immonova_dossier_ads immonova_dossier_ads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_dossier_ads
    ADD CONSTRAINT immonova_dossier_ads_pkey PRIMARY KEY (id);


--
-- Name: immonova_event_media immonova_event_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_event_media
    ADD CONSTRAINT immonova_event_media_pkey PRIMARY KEY (id);


--
-- Name: immonova_events immonova_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_events
    ADD CONSTRAINT immonova_events_pkey PRIMARY KEY (id);


--
-- Name: immonova_events immonova_events_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_events
    ADD CONSTRAINT immonova_events_slug_key UNIQUE (slug);


--
-- Name: immonova_evidence_cache immonova_evidence_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_evidence_cache
    ADD CONSTRAINT immonova_evidence_cache_pkey PRIMARY KEY (id);


--
-- Name: immonova_favorite_opportunities immonova_favorite_opportuniti_subscription_id_opportunity_i_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_favorite_opportunities
    ADD CONSTRAINT immonova_favorite_opportuniti_subscription_id_opportunity_i_key UNIQUE (subscription_id, opportunity_id);


--
-- Name: immonova_favorite_opportunities immonova_favorite_opportunities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_favorite_opportunities
    ADD CONSTRAINT immonova_favorite_opportunities_pkey PRIMARY KEY (id);


--
-- Name: immonova_job_applications immonova_job_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_job_applications
    ADD CONSTRAINT immonova_job_applications_pkey PRIMARY KEY (id);


--
-- Name: immonova_knowledge_assets immonova_knowledge_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_knowledge_assets
    ADD CONSTRAINT immonova_knowledge_assets_pkey PRIMARY KEY (id);


--
-- Name: immonova_manual_overrides immonova_manual_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_manual_overrides
    ADD CONSTRAINT immonova_manual_overrides_pkey PRIMARY KEY (id);


--
-- Name: immonova_market_comparables immonova_market_comparables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_market_comparables
    ADD CONSTRAINT immonova_market_comparables_pkey PRIMARY KEY (id);


--
-- Name: immonova_market_intelligence_cache immonova_market_intelligence_cache_cache_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_market_intelligence_cache
    ADD CONSTRAINT immonova_market_intelligence_cache_cache_key_key UNIQUE (cache_key);


--
-- Name: immonova_market_intelligence_cache immonova_market_intelligence_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_market_intelligence_cache
    ADD CONSTRAINT immonova_market_intelligence_cache_pkey PRIMARY KEY (id);


--
-- Name: immonova_opportunity_views immonova_opportunity_views_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_opportunity_views
    ADD CONSTRAINT immonova_opportunity_views_pkey PRIMARY KEY (id);


--
-- Name: immonova_property_valuations immonova_property_valuations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_property_valuations
    ADD CONSTRAINT immonova_property_valuations_pkey PRIMARY KEY (id);


--
-- Name: immonova_provider_mapping immonova_provider_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_provider_mapping
    ADD CONSTRAINT immonova_provider_mapping_pkey PRIMARY KEY (id);


--
-- Name: immonova_provider_registry immonova_provider_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_provider_registry
    ADD CONSTRAINT immonova_provider_registry_pkey PRIMARY KEY (id);


--
-- Name: immonova_public_accounts immonova_public_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_public_accounts
    ADD CONSTRAINT immonova_public_accounts_pkey PRIMARY KEY (id);


--
-- Name: immonova_push_subscriptions immonova_push_subscriptions_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_push_subscriptions
    ADD CONSTRAINT immonova_push_subscriptions_endpoint_key UNIQUE (endpoint);


--
-- Name: immonova_push_subscriptions immonova_push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_push_subscriptions
    ADD CONSTRAINT immonova_push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: immonova_search_mandates immonova_search_mandates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_search_mandates
    ADD CONSTRAINT immonova_search_mandates_pkey PRIMARY KEY (id);


--
-- Name: immonova_social_posts immonova_social_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_social_posts
    ADD CONSTRAINT immonova_social_posts_pkey PRIMARY KEY (id);


--
-- Name: inquiries inquiries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inquiries
    ADD CONSTRAINT inquiries_pkey PRIMARY KEY (id);


--
-- Name: investor_areas investor_areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_areas
    ADD CONSTRAINT investor_areas_pkey PRIMARY KEY (id);


--
-- Name: investor_categories investor_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_categories
    ADD CONSTRAINT investor_categories_pkey PRIMARY KEY (id);


--
-- Name: investor_requests investor_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_requests
    ADD CONSTRAINT investor_requests_pkey PRIMARY KEY (id);


--
-- Name: investor_seller_properties investor_seller_properties_investor_id_opportunity_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_seller_properties
    ADD CONSTRAINT investor_seller_properties_investor_id_opportunity_id_key UNIQUE (investor_id, opportunity_id);


--
-- Name: investor_seller_properties investor_seller_properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_seller_properties
    ADD CONSTRAINT investor_seller_properties_pkey PRIMARY KEY (id);


--
-- Name: investors investors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investors
    ADD CONSTRAINT investors_pkey PRIMARY KEY (id);


--
-- Name: nda_acceptances nda_acceptances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nda_acceptances
    ADD CONSTRAINT nda_acceptances_pkey PRIMARY KEY (id);


--
-- Name: opportunities opportunities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_pkey PRIMARY KEY (id);


--
-- Name: opportunities opportunities_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_slug_key UNIQUE (slug);


--
-- Name: opportunity_contact_history opportunity_contact_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_contact_history
    ADD CONSTRAINT opportunity_contact_history_pkey PRIMARY KEY (id);


--
-- Name: opportunity_documents opportunity_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_documents
    ADD CONSTRAINT opportunity_documents_pkey PRIMARY KEY (id);


--
-- Name: opportunity_investor_list_items opportunity_investor_list_items_list_id_investor_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_list_items
    ADD CONSTRAINT opportunity_investor_list_items_list_id_investor_id_key UNIQUE (list_id, investor_id);


--
-- Name: opportunity_investor_list_items opportunity_investor_list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_list_items
    ADD CONSTRAINT opportunity_investor_list_items_pkey PRIMARY KEY (id);


--
-- Name: opportunity_investor_lists opportunity_investor_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_lists
    ADD CONSTRAINT opportunity_investor_lists_pkey PRIMARY KEY (id);


--
-- Name: opportunity_reports opportunity_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_reports
    ADD CONSTRAINT opportunity_reports_pkey PRIMARY KEY (id);


--
-- Name: opportunity_timeline opportunity_timeline_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_timeline
    ADD CONSTRAINT opportunity_timeline_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: renovation_images renovation_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renovation_images
    ADD CONSTRAINT renovation_images_pkey PRIMARY KEY (id);


--
-- Name: renovation_renders renovation_renders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renovation_renders
    ADD CONSTRAINT renovation_renders_pkey PRIMARY KEY (id);


--
-- Name: site_settings site_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_settings
    ADD CONSTRAINT site_settings_pkey PRIMARY KEY (id);


--
-- Name: capital_partners_categoria_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX capital_partners_categoria_idx ON public.capital_partners USING btree (categoria);


--
-- Name: capital_partners_priorita_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX capital_partners_priorita_idx ON public.capital_partners USING btree (priorita);


--
-- Name: capital_partners_stato_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX capital_partners_stato_idx ON public.capital_partners USING btree (stato);


--
-- Name: capital_partners_unique_soggetto_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX capital_partners_unique_soggetto_categoria ON public.capital_partners USING btree (soggetto_key, categoria);


--
-- Name: event_invitations_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX event_invitations_created_by_idx ON public.event_invitations USING btree (created_by);


--
-- Name: idx_ad_drafts_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ad_drafts_campaign ON public.immonova_ad_drafts USING btree (campaign_name);


--
-- Name: idx_ad_drafts_opportunity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ad_drafts_opportunity ON public.immonova_ad_drafts USING btree (opportunity_id);


--
-- Name: idx_ad_drafts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ad_drafts_status ON public.immonova_ad_drafts USING btree (status);


--
-- Name: idx_calendar_participants_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_participants_event ON public.immonova_calendar_event_participants USING btree (event_id);


--
-- Name: idx_calendar_participants_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_participants_user ON public.immonova_calendar_event_participants USING btree (user_id);


--
-- Name: idx_calendar_push_subs_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_calendar_push_subs_user ON public.immonova_calendar_push_subscriptions USING btree (user_id);


--
-- Name: idx_destination_photos_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_destination_photos_lookup ON public.immonova_destination_photos USING btree (city, province, region, country_code, active);


--
-- Name: idx_immonova_app_install_leads_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_app_install_leads_created_at ON public.immonova_app_install_leads USING btree (created_at DESC);


--
-- Name: idx_immonova_app_installs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_app_installs_created_at ON public.immonova_app_installs USING btree (created_at);


--
-- Name: idx_immonova_data_sources_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_data_sources_lookup ON public.immonova_data_sources USING btree (category, country_code, region, province, city, enabled, priority);


--
-- Name: idx_immonova_dictionary_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_dictionary_category ON public.immonova_data_dictionary USING btree (category);


--
-- Name: idx_immonova_favorite_opportunities_opportunity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_favorite_opportunities_opportunity ON public.immonova_favorite_opportunities USING btree (opportunity_id);


--
-- Name: idx_immonova_favorite_opportunities_subscription; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_favorite_opportunities_subscription ON public.immonova_favorite_opportunities USING btree (subscription_id);


--
-- Name: idx_immonova_knowledge_assets_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_knowledge_assets_active ON public.immonova_knowledge_assets USING btree (active);


--
-- Name: idx_immonova_knowledge_assets_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_knowledge_assets_category ON public.immonova_knowledge_assets USING btree (category);


--
-- Name: idx_immonova_knowledge_assets_geo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_knowledge_assets_geo ON public.immonova_knowledge_assets USING gist (geo);


--
-- Name: idx_immonova_knowledge_assets_google_place_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_knowledge_assets_google_place_id ON public.immonova_knowledge_assets USING btree (google_place_id);


--
-- Name: idx_immonova_knowledge_assets_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_knowledge_assets_status ON public.immonova_knowledge_assets USING btree (verification_status);


--
-- Name: idx_immonova_knowledge_assets_subtype; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_knowledge_assets_subtype ON public.immonova_knowledge_assets USING btree (subtype);


--
-- Name: idx_immonova_opportunity_views_opportunity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_opportunity_views_opportunity_id ON public.immonova_opportunity_views USING btree (opportunity_id, created_at);


--
-- Name: idx_immonova_push_subscriptions_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_immonova_push_subscriptions_active ON public.immonova_push_subscriptions USING btree (active) WHERE (active = true);


--
-- Name: idx_investors_budget; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_investors_budget ON public.investors USING btree (budget_min, budget_max);


--
-- Name: idx_invitation_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitation_event ON public.event_invitations USING btree (event_id);


--
-- Name: idx_invitation_investor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitation_investor ON public.event_invitations USING btree (investor_id);


--
-- Name: idx_manual_overrides_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_manual_overrides_lookup ON public.immonova_manual_overrides USING btree (category, field_key, active);


--
-- Name: idx_manual_overrides_opportunity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_manual_overrides_opportunity ON public.immonova_manual_overrides USING btree (opportunity_id);


--
-- Name: idx_market_intelligence_cache_geo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_market_intelligence_cache_geo ON public.immonova_market_intelligence_cache USING btree (country_code, region, province, city);


--
-- Name: idx_market_intelligence_cache_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_market_intelligence_cache_key ON public.immonova_market_intelligence_cache USING btree (cache_key);


--
-- Name: idx_opportunities_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunities_category ON public.opportunities USING btree (category);


--
-- Name: idx_opportunities_commercial_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunities_commercial_status ON public.opportunities USING btree (commercial_status);


--
-- Name: idx_opportunities_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunities_published ON public.opportunities USING btree (published);


--
-- Name: idx_opportunity_documents_dossier; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunity_documents_dossier ON public.opportunity_documents USING btree (opportunity_id, include_in_dossier);


--
-- Name: idx_opportunity_timeline_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunity_timeline_event_id ON public.opportunity_timeline USING btree (event_id);


--
-- Name: idx_opportunity_timeline_opportunity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunity_timeline_opportunity_id ON public.opportunity_timeline USING btree (opportunity_id);


--
-- Name: idx_provider_mapping_dictionary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_mapping_dictionary ON public.immonova_provider_mapping USING btree (dictionary_field);


--
-- Name: idx_provider_mapping_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_mapping_provider ON public.immonova_provider_mapping USING btree (provider_id);


--
-- Name: idx_social_posts_opportunity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_social_posts_opportunity ON public.immonova_social_posts USING btree (opportunity_id);


--
-- Name: idx_social_posts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_social_posts_status ON public.immonova_social_posts USING btree (status);


--
-- Name: imc_country_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX imc_country_idx ON public.immonova_market_comparables USING btree (country_code, is_active, verification_status);


--
-- Name: imc_geo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX imc_geo_idx ON public.immonova_market_comparables USING btree (country_code, region, province, municipality, city);


--
-- Name: imc_metric_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX imc_metric_idx ON public.immonova_market_comparables USING btree (adr, occupancy, revpar);


--
-- Name: imc_source_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX imc_source_idx ON public.immonova_market_comparables USING btree (source_url);


--
-- Name: imc_source_record_unique_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX imc_source_record_unique_idx ON public.immonova_market_comparables USING btree (country_code, COALESCE(municipality, city, area_name, ''::text), COALESCE(property_external_id, property_name, ''::text), observation_year, COALESCE(observation_period, ''::text), source_url, COALESCE(adr, ('-1'::integer)::numeric), COALESCE(occupancy, ('-1'::integer)::numeric), COALESCE(revpar, ('-1'::integer)::numeric));


--
-- Name: imc_year_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX imc_year_idx ON public.immonova_market_comparables USING btree (observation_year DESC);


--
-- Name: immonova_access_logs_login_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX immonova_access_logs_login_at_idx ON public.immonova_access_logs USING btree (login_at DESC);


--
-- Name: immonova_access_logs_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX immonova_access_logs_user_id_idx ON public.immonova_access_logs USING btree (user_id);


--
-- Name: immonova_event_media_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX immonova_event_media_event_idx ON public.immonova_event_media USING btree (event_id, sort_order);


--
-- Name: immonova_events_published_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX immonova_events_published_idx ON public.immonova_events USING btree (published, event_type, event_date DESC);


--
-- Name: immonova_provider_registry_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX immonova_provider_registry_lookup_idx ON public.immonova_provider_registry USING btree (domain, enabled, country_code, region, province, city, priority);


--
-- Name: investors_created_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX investors_created_by_idx ON public.investors USING btree (created_by);


--
-- Name: investors_email_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX investors_email_idx ON public.investors USING btree (email);


--
-- Name: investors_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX investors_phone_idx ON public.investors USING btree (phone);


--
-- Name: investors_whatsapp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX investors_whatsapp_idx ON public.investors USING btree (whatsapp);


--
-- Name: opportunity_documents_opportunity_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opportunity_documents_opportunity_id_idx ON public.opportunity_documents USING btree (opportunity_id);


--
-- Name: opportunity_documents_opportunity_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX opportunity_documents_opportunity_type_idx ON public.opportunity_documents USING btree (opportunity_id, document_type);


--
-- Name: immonova_events immonova_events_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immonova_events_set_updated_at BEFORE UPDATE ON public.immonova_events FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: opportunities immonova_guard_opportunity_edit_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immonova_guard_opportunity_edit_trigger BEFORE UPDATE ON public.opportunities FOR EACH ROW EXECUTE FUNCTION public.immonova_guard_opportunity_edit();


--
-- Name: immonova_ad_drafts trg_ad_drafts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ad_drafts_updated_at BEFORE UPDATE ON public.immonova_ad_drafts FOR EACH ROW EXECUTE FUNCTION public.immonova_ad_drafts_set_updated_at();


--
-- Name: immonova_knowledge_assets trg_immonova_knowledge_assets_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_immonova_knowledge_assets_updated_at BEFORE UPDATE ON public.immonova_knowledge_assets FOR EACH ROW EXECUTE FUNCTION public.set_immonova_knowledge_assets_updated_at();


--
-- Name: immonova_market_comparables trg_immonova_market_comparables_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_immonova_market_comparables_updated_at BEFORE UPDATE ON public.immonova_market_comparables FOR EACH ROW EXECUTE FUNCTION public.immonova_set_updated_at();


--
-- Name: immonova_app_installs trg_notify_admin_on_install; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_admin_on_install AFTER INSERT ON public.immonova_app_installs FOR EACH ROW EXECUTE FUNCTION public.notify_admin_on_app_install();


--
-- Name: immonova_social_posts trg_social_posts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_social_posts_updated_at BEFORE UPDATE ON public.immonova_social_posts FOR EACH ROW EXECUTE FUNCTION public.immonova_social_posts_set_updated_at();


--
-- Name: capital_partners capital_partners_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capital_partners
    ADD CONSTRAINT capital_partners_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: capital_partners_grants capital_partners_grants_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capital_partners_grants
    ADD CONSTRAINT capital_partners_grants_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.profiles(id);


--
-- Name: capital_partners_grants capital_partners_grants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capital_partners_grants
    ADD CONSTRAINT capital_partners_grants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: dossier_requests dossier_requests_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dossier_requests
    ADD CONSTRAINT dossier_requests_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: event_invitations event_invitations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invitations
    ADD CONSTRAINT event_invitations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: event_invitations event_invitations_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invitations
    ADD CONSTRAINT event_invitations_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.immonova_events(id) ON DELETE CASCADE;


--
-- Name: event_invitations event_invitations_investor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event_invitations
    ADD CONSTRAINT event_invitations_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES public.investors(id) ON DELETE CASCADE;


--
-- Name: immonova_access_logs immonova_access_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_access_logs
    ADD CONSTRAINT immonova_access_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: immonova_ad_drafts immonova_ad_drafts_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_ad_drafts
    ADD CONSTRAINT immonova_ad_drafts_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id);


--
-- Name: immonova_ad_drafts immonova_ad_drafts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_ad_drafts
    ADD CONSTRAINT immonova_ad_drafts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: immonova_ad_drafts immonova_ad_drafts_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_ad_drafts
    ADD CONSTRAINT immonova_ad_drafts_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE SET NULL;


--
-- Name: immonova_calendar_event_participants immonova_calendar_event_participants_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_event_participants
    ADD CONSTRAINT immonova_calendar_event_participants_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.immonova_calendar_events(id) ON DELETE CASCADE;


--
-- Name: immonova_calendar_event_participants immonova_calendar_event_participants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_event_participants
    ADD CONSTRAINT immonova_calendar_event_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: immonova_calendar_events immonova_calendar_events_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_events
    ADD CONSTRAINT immonova_calendar_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: immonova_calendar_events immonova_calendar_events_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_events
    ADD CONSTRAINT immonova_calendar_events_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id);


--
-- Name: immonova_calendar_push_subscriptions immonova_calendar_push_subscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_calendar_push_subscriptions
    ADD CONSTRAINT immonova_calendar_push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: immonova_event_media immonova_event_media_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_event_media
    ADD CONSTRAINT immonova_event_media_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.immonova_events(id) ON DELETE CASCADE;


--
-- Name: immonova_events immonova_events_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_events
    ADD CONSTRAINT immonova_events_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE SET NULL;


--
-- Name: immonova_favorite_opportunities immonova_favorite_opportunities_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_favorite_opportunities
    ADD CONSTRAINT immonova_favorite_opportunities_account_id_fkey FOREIGN KEY (account_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: immonova_favorite_opportunities immonova_favorite_opportunities_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_favorite_opportunities
    ADD CONSTRAINT immonova_favorite_opportunities_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: immonova_favorite_opportunities immonova_favorite_opportunities_subscription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_favorite_opportunities
    ADD CONSTRAINT immonova_favorite_opportunities_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES public.immonova_push_subscriptions(id) ON DELETE CASCADE;


--
-- Name: immonova_knowledge_assets immonova_knowledge_assets_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_knowledge_assets
    ADD CONSTRAINT immonova_knowledge_assets_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: immonova_knowledge_assets immonova_knowledge_assets_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_knowledge_assets
    ADD CONSTRAINT immonova_knowledge_assets_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: immonova_manual_overrides immonova_manual_overrides_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_manual_overrides
    ADD CONSTRAINT immonova_manual_overrides_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: immonova_opportunity_views immonova_opportunity_views_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_opportunity_views
    ADD CONSTRAINT immonova_opportunity_views_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: immonova_property_valuations immonova_property_valuations_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_property_valuations
    ADD CONSTRAINT immonova_property_valuations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: immonova_provider_mapping immonova_provider_mapping_dictionary_field_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_provider_mapping
    ADD CONSTRAINT immonova_provider_mapping_dictionary_field_fkey FOREIGN KEY (dictionary_field) REFERENCES public.immonova_data_dictionary(field_key);


--
-- Name: immonova_provider_mapping immonova_provider_mapping_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_provider_mapping
    ADD CONSTRAINT immonova_provider_mapping_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.immonova_data_sources(id) ON DELETE CASCADE;


--
-- Name: immonova_public_accounts immonova_public_accounts_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_public_accounts
    ADD CONSTRAINT immonova_public_accounts_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: immonova_push_subscriptions immonova_push_subscriptions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_push_subscriptions
    ADD CONSTRAINT immonova_push_subscriptions_account_id_fkey FOREIGN KEY (account_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: immonova_search_mandates immonova_search_mandates_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_search_mandates
    ADD CONSTRAINT immonova_search_mandates_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: immonova_social_posts immonova_social_posts_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_social_posts
    ADD CONSTRAINT immonova_social_posts_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id);


--
-- Name: immonova_social_posts immonova_social_posts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_social_posts
    ADD CONSTRAINT immonova_social_posts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: immonova_social_posts immonova_social_posts_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.immonova_social_posts
    ADD CONSTRAINT immonova_social_posts_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE SET NULL;


--
-- Name: inquiries inquiries_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inquiries
    ADD CONSTRAINT inquiries_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: investor_areas investor_areas_investor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_areas
    ADD CONSTRAINT investor_areas_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES public.investors(id) ON DELETE CASCADE;


--
-- Name: investor_categories investor_categories_investor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_categories
    ADD CONSTRAINT investor_categories_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES public.investors(id) ON DELETE CASCADE;


--
-- Name: investor_requests investor_requests_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_requests
    ADD CONSTRAINT investor_requests_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE SET NULL;


--
-- Name: investor_seller_properties investor_seller_properties_investor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_seller_properties
    ADD CONSTRAINT investor_seller_properties_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES public.investors(id) ON DELETE CASCADE;


--
-- Name: investor_seller_properties investor_seller_properties_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investor_seller_properties
    ADD CONSTRAINT investor_seller_properties_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: investors investors_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investors
    ADD CONSTRAINT investors_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: nda_acceptances nda_acceptances_dossier_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nda_acceptances
    ADD CONSTRAINT nda_acceptances_dossier_request_id_fkey FOREIGN KEY (dossier_request_id) REFERENCES public.dossier_requests(id) ON DELETE CASCADE;


--
-- Name: nda_acceptances nda_acceptances_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nda_acceptances
    ADD CONSTRAINT nda_acceptances_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: opportunities opportunities_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id);


--
-- Name: opportunities opportunities_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id);


--
-- Name: opportunities opportunities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: opportunities opportunities_user_profile_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_user_profile_fk FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: opportunity_contact_history opportunity_contact_history_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_contact_history
    ADD CONSTRAINT opportunity_contact_history_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: opportunity_contact_history opportunity_contact_history_investor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_contact_history
    ADD CONSTRAINT opportunity_contact_history_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES public.investors(id) ON DELETE CASCADE;


--
-- Name: opportunity_contact_history opportunity_contact_history_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_contact_history
    ADD CONSTRAINT opportunity_contact_history_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.opportunity_investor_lists(id) ON DELETE SET NULL;


--
-- Name: opportunity_contact_history opportunity_contact_history_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_contact_history
    ADD CONSTRAINT opportunity_contact_history_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: opportunity_documents opportunity_documents_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_documents
    ADD CONSTRAINT opportunity_documents_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: opportunity_documents opportunity_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_documents
    ADD CONSTRAINT opportunity_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: opportunity_investor_list_items opportunity_investor_list_items_investor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_list_items
    ADD CONSTRAINT opportunity_investor_list_items_investor_id_fkey FOREIGN KEY (investor_id) REFERENCES public.investors(id) ON DELETE CASCADE;


--
-- Name: opportunity_investor_list_items opportunity_investor_list_items_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_list_items
    ADD CONSTRAINT opportunity_investor_list_items_list_id_fkey FOREIGN KEY (list_id) REFERENCES public.opportunity_investor_lists(id) ON DELETE CASCADE;


--
-- Name: opportunity_investor_lists opportunity_investor_lists_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_lists
    ADD CONSTRAINT opportunity_investor_lists_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: opportunity_investor_lists opportunity_investor_lists_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_investor_lists
    ADD CONSTRAINT opportunity_investor_lists_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: opportunity_reports opportunity_reports_generated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_reports
    ADD CONSTRAINT opportunity_reports_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES auth.users(id);


--
-- Name: opportunity_reports opportunity_reports_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_reports
    ADD CONSTRAINT opportunity_reports_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: opportunity_timeline opportunity_timeline_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_timeline
    ADD CONSTRAINT opportunity_timeline_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: opportunity_timeline opportunity_timeline_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunity_timeline
    ADD CONSTRAINT opportunity_timeline_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: renovation_images renovation_images_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renovation_images
    ADD CONSTRAINT renovation_images_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: renovation_renders renovation_renders_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renovation_renders
    ADD CONSTRAINT renovation_renders_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: immonova_dossier_ads Allow authenticated delete on immonova_dossier_ads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated delete on immonova_dossier_ads" ON public.immonova_dossier_ads FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_job_applications Allow authenticated delete on immonova_job_applications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated delete on immonova_job_applications" ON public.immonova_job_applications FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_property_valuations Allow authenticated delete on immonova_property_valuations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated delete on immonova_property_valuations" ON public.immonova_property_valuations FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_search_mandates Allow authenticated delete on immonova_search_mandates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated delete on immonova_search_mandates" ON public.immonova_search_mandates FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_property_valuations Allow authenticated insert on immonova_property_valuations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated insert on immonova_property_valuations" ON public.immonova_property_valuations FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_search_mandates Allow authenticated insert on immonova_search_mandates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated insert on immonova_search_mandates" ON public.immonova_search_mandates FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: opportunities Allow authenticated insert on opportunities; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated insert on opportunities" ON public.opportunities FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_calendar_busy_blocks Allow authenticated read on immonova_calendar_busy_blocks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read on immonova_calendar_busy_blocks" ON public.immonova_calendar_busy_blocks FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_dossier_ads Allow authenticated read on immonova_dossier_ads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read on immonova_dossier_ads" ON public.immonova_dossier_ads FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_job_applications Allow authenticated read on immonova_job_applications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read on immonova_job_applications" ON public.immonova_job_applications FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_property_valuations Allow authenticated read on immonova_property_valuations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read on immonova_property_valuations" ON public.immonova_property_valuations FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_search_mandates Allow authenticated read on immonova_search_mandates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read on immonova_search_mandates" ON public.immonova_search_mandates FOR SELECT TO authenticated USING (true);


--
-- Name: opportunities Allow authenticated read on opportunities; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read on opportunities" ON public.opportunities FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_dossier_ads Allow authenticated update on immonova_dossier_ads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated update on immonova_dossier_ads" ON public.immonova_dossier_ads FOR UPDATE TO authenticated USING (true);


--
-- Name: immonova_property_valuations Allow authenticated update on immonova_property_valuations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated update on immonova_property_valuations" ON public.immonova_property_valuations FOR UPDATE TO authenticated USING (true);


--
-- Name: immonova_search_mandates Allow authenticated update on immonova_search_mandates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated update on immonova_search_mandates" ON public.immonova_search_mandates FOR UPDATE TO authenticated USING (true);


--
-- Name: opportunities Allow authenticated update on opportunities; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated update on opportunities" ON public.opportunities FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_dossier_ads Allow authenticated write on immonova_dossier_ads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated write on immonova_dossier_ads" ON public.immonova_dossier_ads FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_job_applications Allow public insert on immonova_job_applications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public insert on immonova_job_applications" ON public.immonova_job_applications FOR INSERT TO anon WITH CHECK (true);


--
-- Name: immonova_dossier_ads Allow public read active ads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public read active ads" ON public.immonova_dossier_ads FOR SELECT TO anon USING ((active = true));


--
-- Name: inquiries Anyone can create inquiries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can create inquiries" ON public.inquiries FOR INSERT TO anon WITH CHECK (true);


--
-- Name: inquiries Authenticated can manage inquiries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated can manage inquiries" ON public.inquiries TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_destination_photos Authenticated users can manage destination photos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can manage destination photos" ON public.immonova_destination_photos TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_manual_overrides Authenticated users can manage manual overrides; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can manage manual overrides" ON public.immonova_manual_overrides TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_market_comparables Read verified market comparables; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Read verified market comparables" ON public.immonova_market_comparables FOR SELECT TO authenticated USING (((is_active = true) AND (verification_status = 'verified'::text)));


--
-- Name: immonova_calendar_busy_blocks Service role write on immonova_calendar_busy_blocks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role write on immonova_calendar_busy_blocks" ON public.immonova_calendar_busy_blocks TO service_role USING (true) WITH CHECK (true);


--
-- Name: immonova_favorite_opportunities account can manage own favorites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "account can manage own favorites" ON public.immonova_favorite_opportunities TO authenticated USING ((auth.uid() = account_id)) WITH CHECK ((auth.uid() = account_id));


--
-- Name: immonova_ad_drafts ad_drafts_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ad_drafts_select_admin ON public.immonova_ad_drafts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));


--
-- Name: immonova_ad_drafts ad_drafts_write_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ad_drafts_write_admin ON public.immonova_ad_drafts TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));


--
-- Name: opportunities admin_delete_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_delete_all ON public.opportunities FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: categories admin_manage_categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_manage_categories ON public.categories TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: opportunity_reports admin_manage_opportunity_reports; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_manage_opportunity_reports ON public.opportunity_reports TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: opportunities admin_select_all_user_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_select_all_user_select_own ON public.opportunities FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))));


--
-- Name: dossier_requests admin_select_dossier_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_select_dossier_requests ON public.dossier_requests FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: investor_requests admin_select_investor_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_select_investor_requests ON public.investor_requests FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'ceo'::text]))))));


--
-- Name: nda_acceptances admin_select_nda_acceptances; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_select_nda_acceptances ON public.nda_acceptances FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: dossier_requests admin_update_dossier_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_update_dossier_requests ON public.dossier_requests FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: investor_requests admin_update_investor_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_update_investor_requests ON public.investor_requests FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'ceo'::text])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'ceo'::text]))))));


--
-- Name: site_settings admins_can_insert_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admins_can_insert_settings ON public.site_settings FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: site_settings admins_can_update_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admins_can_update_settings ON public.site_settings FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: immonova_access_logs admins_read_access_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admins_read_access_logs ON public.immonova_access_logs FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: site_settings anyone_can_read_settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY anyone_can_read_settings ON public.site_settings FOR SELECT TO authenticated, anon USING (true);


--
-- Name: opportunity_timeline authenticated can delete milestones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can delete milestones" ON public.opportunity_timeline FOR DELETE TO authenticated USING (true);


--
-- Name: opportunity_timeline authenticated can insert milestones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can insert milestones" ON public.opportunity_timeline FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: opportunity_timeline authenticated can read all milestones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can read all milestones" ON public.opportunity_timeline FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_app_installs authenticated can read installs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can read installs" ON public.immonova_app_installs FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_app_install_leads authenticated can read leads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can read leads" ON public.immonova_app_install_leads FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_opportunity_views authenticated can read views; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can read views" ON public.immonova_opportunity_views FOR SELECT TO authenticated USING (true);


--
-- Name: opportunity_timeline authenticated can update milestones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated can update milestones" ON public.opportunity_timeline FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_calendar_busy_blocks calendar_busy_blocks_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_busy_blocks_select ON public.immonova_calendar_busy_blocks FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_calendar_events calendar_events_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_events_delete ON public.immonova_calendar_events FOR DELETE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: immonova_calendar_events calendar_events_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_events_insert ON public.immonova_calendar_events FOR INSERT TO authenticated WITH CHECK ((created_by = auth.uid()));


--
-- Name: immonova_calendar_events calendar_events_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_events_select ON public.immonova_calendar_events FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))) OR (created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = immonova_calendar_events.created_by) AND (p.role = 'admin'::text)))) OR public.is_calendar_participant(id, auth.uid())));


--
-- Name: immonova_calendar_events calendar_events_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_events_update ON public.immonova_calendar_events FOR UPDATE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))) WITH CHECK (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: immonova_calendar_event_participants calendar_participants_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_participants_delete ON public.immonova_calendar_event_participants FOR DELETE TO authenticated USING (public.is_calendar_event_owner_or_admin(event_id, auth.uid()));


--
-- Name: immonova_calendar_event_participants calendar_participants_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_participants_insert ON public.immonova_calendar_event_participants FOR INSERT TO authenticated WITH CHECK (public.is_calendar_event_owner_or_admin(event_id, auth.uid()));


--
-- Name: immonova_calendar_event_participants calendar_participants_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_participants_select ON public.immonova_calendar_event_participants FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))) OR public.is_calendar_event_owner_or_admin(event_id, auth.uid())));


--
-- Name: immonova_calendar_push_subscriptions calendar_push_subs_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_push_subs_delete ON public.immonova_calendar_push_subscriptions FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: immonova_calendar_push_subscriptions calendar_push_subs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_push_subs_insert ON public.immonova_calendar_push_subscriptions FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: immonova_calendar_push_subscriptions calendar_push_subs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY calendar_push_subs_select ON public.immonova_calendar_push_subscriptions FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: capital_partners; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.capital_partners ENABLE ROW LEVEL SECURITY;

--
-- Name: capital_partners capital_partners_delete_restricted; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capital_partners_delete_restricted ON public.capital_partners FOR DELETE USING (public.has_capital_partners_access());


--
-- Name: capital_partners_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.capital_partners_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: capital_partners_grants capital_partners_grants_owner_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capital_partners_grants_owner_all ON public.capital_partners_grants USING (public.is_capital_partners_owner()) WITH CHECK (public.is_capital_partners_owner());


--
-- Name: capital_partners capital_partners_insert_restricted; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capital_partners_insert_restricted ON public.capital_partners FOR INSERT WITH CHECK (public.has_capital_partners_access());


--
-- Name: capital_partners capital_partners_select_restricted; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capital_partners_select_restricted ON public.capital_partners FOR SELECT USING (public.has_capital_partners_access());


--
-- Name: capital_partners capital_partners_update_restricted; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY capital_partners_update_restricted ON public.capital_partners FOR UPDATE USING (public.has_capital_partners_access()) WITH CHECK (public.has_capital_partners_access());


--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: dossier_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dossier_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: event_invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.event_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: event_invitations event_invitations_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invitations_delete ON public.event_invitations FOR DELETE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: event_invitations event_invitations_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invitations_insert ON public.event_invitations FOR INSERT TO authenticated WITH CHECK ((created_by = auth.uid()));


--
-- Name: event_invitations event_invitations_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invitations_select ON public.event_invitations FOR SELECT TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: event_invitations event_invitations_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY event_invitations_update ON public.event_invitations FOR UPDATE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))) WITH CHECK (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: immonova_access_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_access_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_ad_drafts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_ad_drafts ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_app_install_leads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_app_install_leads ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_app_installs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_app_installs ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_calendar_busy_blocks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_calendar_busy_blocks ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_calendar_event_participants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_calendar_event_participants ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_calendar_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_calendar_events ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_calendar_push_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_calendar_push_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_contact_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_contact_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_data_dictionary; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_data_dictionary ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_data_sources; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_data_sources ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_data_sources immonova_data_sources_delete_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_data_sources_delete_authenticated ON public.immonova_data_sources FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_data_sources immonova_data_sources_insert_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_data_sources_insert_authenticated ON public.immonova_data_sources FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_data_sources immonova_data_sources_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_data_sources_select_authenticated ON public.immonova_data_sources FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_data_sources immonova_data_sources_update_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_data_sources_update_authenticated ON public.immonova_data_sources FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_destination_photos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_destination_photos ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_dossier_ads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_dossier_ads ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_event_media; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_event_media ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_event_media immonova_event_media_auth_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_event_media_auth_delete ON public.immonova_event_media FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_event_media immonova_event_media_auth_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_event_media_auth_insert ON public.immonova_event_media FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_event_media immonova_event_media_auth_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_event_media_auth_update ON public.immonova_event_media FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_event_media immonova_event_media_public_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_event_media_public_select ON public.immonova_event_media FOR SELECT TO authenticated, anon USING ((EXISTS ( SELECT 1
   FROM public.immonova_events e
  WHERE ((e.id = immonova_event_media.event_id) AND ((e.published = true) OR (auth.role() = 'authenticated'::text))))));


--
-- Name: immonova_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_events ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_events immonova_events_auth_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_events_auth_delete ON public.immonova_events FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_events immonova_events_auth_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_events_auth_insert ON public.immonova_events FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_events immonova_events_auth_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_events_auth_update ON public.immonova_events FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: immonova_events immonova_events_public_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY immonova_events_public_select ON public.immonova_events FOR SELECT TO authenticated, anon USING (((published = true) OR (auth.role() = 'authenticated'::text)));


--
-- Name: immonova_evidence_cache; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_evidence_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_favorite_opportunities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_favorite_opportunities ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_job_applications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_job_applications ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_knowledge_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_knowledge_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_manual_overrides; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_manual_overrides ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_market_comparables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_market_comparables ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_market_intelligence_cache; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_market_intelligence_cache ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_opportunity_views; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_opportunity_views ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_property_valuations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_property_valuations ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_provider_mapping; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_provider_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_provider_registry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_provider_registry ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_public_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_public_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_push_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_push_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_search_mandates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_search_mandates ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_social_posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.immonova_social_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: inquiries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_access_logs insert_own_access_log; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY insert_own_access_log ON public.immonova_access_logs FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: investor_areas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.investor_areas ENABLE ROW LEVEL SECURITY;

--
-- Name: investor_areas investor_areas_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_areas_delete ON public.investor_areas FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.investors i
  WHERE ((i.id = investor_areas.investor_id) AND ((i.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: investor_areas investor_areas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_areas_insert ON public.investor_areas FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.investors i
  WHERE ((i.id = investor_areas.investor_id) AND ((i.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: investor_areas investor_areas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_areas_select ON public.investor_areas FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.investors i
  WHERE ((i.id = investor_areas.investor_id) AND ((i.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: investor_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.investor_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: investor_categories investor_categories_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_categories_delete ON public.investor_categories FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.investors i
  WHERE ((i.id = investor_categories.investor_id) AND ((i.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: investor_categories investor_categories_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_categories_insert ON public.investor_categories FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.investors i
  WHERE ((i.id = investor_categories.investor_id) AND ((i.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: investor_categories investor_categories_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_categories_select ON public.investor_categories FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.investors i
  WHERE ((i.id = investor_categories.investor_id) AND ((i.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: investor_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.investor_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: investor_requests investor_requests_delete_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_requests_delete_authenticated ON public.investor_requests FOR DELETE TO authenticated USING (true);


--
-- Name: investor_requests investor_requests_insert_public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_requests_insert_public ON public.investor_requests FOR INSERT TO authenticated, anon WITH CHECK (((first_name IS NOT NULL) AND (last_name IS NOT NULL) AND (email IS NOT NULL) AND (phone IS NOT NULL) AND (country IS NOT NULL) AND (preferred_language IS NOT NULL) AND (nda_accepted = true) AND (request_completed = true) AND (completion_status IS NOT NULL) AND (approved = false) AND (dossier_sent = false)));


--
-- Name: investor_requests investor_requests_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_requests_select_authenticated ON public.investor_requests FOR SELECT TO authenticated USING (true);


--
-- Name: investor_requests investor_requests_update_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_requests_update_authenticated ON public.investor_requests FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: investor_seller_properties; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.investor_seller_properties ENABLE ROW LEVEL SECURITY;

--
-- Name: investor_seller_properties investor_seller_properties_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_seller_properties_delete ON public.investor_seller_properties FOR DELETE TO authenticated USING (true);


--
-- Name: investor_seller_properties investor_seller_properties_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_seller_properties_insert ON public.investor_seller_properties FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: investor_seller_properties investor_seller_properties_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_seller_properties_select ON public.investor_seller_properties FOR SELECT TO authenticated USING (true);


--
-- Name: investor_seller_properties investor_seller_properties_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investor_seller_properties_update ON public.investor_seller_properties FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: investors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.investors ENABLE ROW LEVEL SECURITY;

--
-- Name: investors investors_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investors_delete ON public.investors FOR DELETE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: investors investors_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investors_insert ON public.investors FOR INSERT TO authenticated WITH CHECK ((created_by = auth.uid()));


--
-- Name: investors investors_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investors_select ON public.investors FOR SELECT TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: investors investors_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY investors_update ON public.investors FOR UPDATE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))) WITH CHECK (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: immonova_knowledge_assets knowledge_assets_delete_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY knowledge_assets_delete_authenticated ON public.immonova_knowledge_assets FOR DELETE TO authenticated USING (true);


--
-- Name: immonova_knowledge_assets knowledge_assets_insert_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY knowledge_assets_insert_authenticated ON public.immonova_knowledge_assets FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: immonova_knowledge_assets knowledge_assets_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY knowledge_assets_select_authenticated ON public.immonova_knowledge_assets FOR SELECT TO authenticated USING (true);


--
-- Name: immonova_knowledge_assets knowledge_assets_update_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY knowledge_assets_update_authenticated ON public.immonova_knowledge_assets FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: nda_acceptances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.nda_acceptances ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunities ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunity_contact_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_contact_history ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunity_contact_history opportunity_contact_history_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_contact_history_insert ON public.opportunity_contact_history FOR INSERT TO authenticated WITH CHECK ((created_by = auth.uid()));


--
-- Name: opportunity_contact_history opportunity_contact_history_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_contact_history_select ON public.opportunity_contact_history FOR SELECT TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: opportunity_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunity_documents opportunity_documents_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_documents_delete ON public.opportunity_documents FOR DELETE USING ((auth.role() = 'authenticated'::text));


--
-- Name: opportunity_documents opportunity_documents_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_documents_insert ON public.opportunity_documents FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: opportunity_documents opportunity_documents_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_documents_select ON public.opportunity_documents FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: opportunity_documents opportunity_documents_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_documents_update ON public.opportunity_documents FOR UPDATE USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: opportunity_investor_list_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_investor_list_items ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunity_investor_lists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_investor_lists ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunity_investor_list_items opportunity_list_items_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_list_items_delete ON public.opportunity_investor_list_items FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.opportunity_investor_lists l
  WHERE ((l.id = opportunity_investor_list_items.list_id) AND ((l.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: opportunity_investor_list_items opportunity_list_items_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_list_items_insert ON public.opportunity_investor_list_items FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.opportunity_investor_lists l
  WHERE ((l.id = opportunity_investor_list_items.list_id) AND ((l.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: opportunity_investor_list_items opportunity_list_items_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_list_items_select ON public.opportunity_investor_list_items FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.opportunity_investor_lists l
  WHERE ((l.id = opportunity_investor_list_items.list_id) AND ((l.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: opportunity_investor_list_items opportunity_list_items_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_list_items_update ON public.opportunity_investor_list_items FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.opportunity_investor_lists l
  WHERE ((l.id = opportunity_investor_list_items.list_id) AND ((l.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.opportunity_investor_lists l
  WHERE ((l.id = opportunity_investor_list_items.list_id) AND ((l.created_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))))));


--
-- Name: opportunity_investor_lists opportunity_lists_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_lists_delete ON public.opportunity_investor_lists FOR DELETE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: opportunity_investor_lists opportunity_lists_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_lists_insert ON public.opportunity_investor_lists FOR INSERT TO authenticated WITH CHECK ((created_by = auth.uid()));


--
-- Name: opportunity_investor_lists opportunity_lists_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_lists_select ON public.opportunity_investor_lists FOR SELECT TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: opportunity_investor_lists opportunity_lists_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY opportunity_lists_update ON public.opportunity_investor_lists FOR UPDATE TO authenticated USING (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))))) WITH CHECK (((created_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))));


--
-- Name: opportunity_reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_reports ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunity_timeline; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunity_timeline ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select_own_or_admin ON public.profiles FOR SELECT TO authenticated USING (((id = auth.uid()) OR public.is_admin()));


--
-- Name: profiles profiles_update_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_admin_only ON public.profiles FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: immonova_push_subscriptions public can deactivate own subscription by endpoint; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can deactivate own subscription by endpoint" ON public.immonova_push_subscriptions FOR UPDATE TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: immonova_app_install_leads public can insert own lead; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can insert own lead" ON public.immonova_app_install_leads FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: immonova_push_subscriptions public can insert own subscription; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can insert own subscription" ON public.immonova_push_subscriptions FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: immonova_app_installs public can log installs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can log installs" ON public.immonova_app_installs FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: immonova_opportunity_views public can log views; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can log views" ON public.immonova_opportunity_views FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: opportunity_timeline public can read public milestones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can read public milestones" ON public.opportunity_timeline FOR SELECT TO anon USING ((visibility = 'public'::text));


--
-- Name: immonova_contact_requests public can submit contact request; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can submit contact request" ON public.immonova_contact_requests FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: dossier_requests public_insert_dossier_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_insert_dossier_requests ON public.dossier_requests FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: investor_requests public_insert_investor_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_insert_investor_requests ON public.investor_requests FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: nda_acceptances public_insert_nda_acceptances; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_insert_nda_acceptances ON public.nda_acceptances FOR INSERT TO authenticated, anon WITH CHECK (true);


--
-- Name: categories public_select_active_categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_select_active_categories ON public.categories FOR SELECT TO authenticated, anon USING ((active = true));


--
-- Name: opportunities public_select_published_opportunities; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY public_select_published_opportunities ON public.opportunities FOR SELECT TO anon USING ((published = true));


--
-- Name: renovation_images; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.renovation_images ENABLE ROW LEVEL SECURITY;

--
-- Name: renovation_images renovation_images_delete_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_images_delete_authenticated ON public.renovation_images FOR DELETE TO authenticated USING (true);


--
-- Name: renovation_images renovation_images_insert_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_images_insert_authenticated ON public.renovation_images FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: renovation_images renovation_images_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_images_select_authenticated ON public.renovation_images FOR SELECT TO authenticated USING (true);


--
-- Name: renovation_images renovation_images_update_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_images_update_authenticated ON public.renovation_images FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: renovation_renders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.renovation_renders ENABLE ROW LEVEL SECURITY;

--
-- Name: renovation_renders renovation_renders_delete_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_renders_delete_authenticated ON public.renovation_renders FOR DELETE TO authenticated USING (true);


--
-- Name: renovation_renders renovation_renders_insert_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_renders_insert_authenticated ON public.renovation_renders FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: renovation_renders renovation_renders_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_renders_select_authenticated ON public.renovation_renders FOR SELECT TO authenticated USING (true);


--
-- Name: renovation_renders renovation_renders_update_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY renovation_renders_update_authenticated ON public.renovation_renders FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: site_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: immonova_social_posts social_posts_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY social_posts_select_admin ON public.immonova_social_posts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));


--
-- Name: immonova_social_posts social_posts_write_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY social_posts_write_admin ON public.immonova_social_posts TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = 'admin'::text)))));


--
-- Name: immonova_app_install_leads staff can delete leads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can delete leads" ON public.immonova_app_install_leads FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['admin'::text, 'collaborator'::text]))))));


--
-- Name: immonova_public_accounts staff can read all accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can read all accounts" ON public.immonova_public_accounts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['admin'::text, 'collaborator'::text]))))));


--
-- Name: immonova_favorite_opportunities staff can read all favorites; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can read all favorites" ON public.immonova_favorite_opportunities FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['admin'::text, 'collaborator'::text]))))));


--
-- Name: immonova_contact_requests staff can read contact requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "staff can read contact requests" ON public.immonova_contact_requests FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['admin'::text, 'collaborator'::text]))))));


--
-- Name: immonova_public_accounts user can insert own account; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "user can insert own account" ON public.immonova_public_accounts FOR INSERT TO authenticated WITH CHECK ((auth.uid() = id));


--
-- Name: immonova_public_accounts user can read own account; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "user can read own account" ON public.immonova_public_accounts FOR SELECT TO authenticated USING ((auth.uid() = id));


--
-- Name: immonova_public_accounts user can update own account; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "user can update own account" ON public.immonova_public_accounts FOR UPDATE TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));


--
-- Name: opportunities user_insert_only_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_insert_only_own ON public.opportunities FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: opportunities user_update_own_admin_update_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY user_update_own_admin_update_all ON public.opportunities FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))))) WITH CHECK (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text))))));


--
-- PostgreSQL database dump complete
--

\unrestrict JGYck7yvQcy780buYD8Mjvgp3PziUByob3O1kljOj7NHFEuX8mGRH5sSdOHeREl

