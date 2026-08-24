-- =====================================================================
-- IMMONOVA — composizione camere/alloggi per corpo di fabbrica, sulla
-- tabella esistente opportunities. Sicuro da rieseguire più volte.
--
-- Struttura del JSON salvato in room_inventory (array di "corpi di
-- fabbrica" / edifici):
-- [
--   {
--     "name": "Corpo 1 - Villa principale",
--     "roomTypes": [
--       {"type":"singola", "customLabel":"", "count": 4},
--       {"type":"suite",   "customLabel":"", "count": 2},
--       {"type":"altro",   "customLabel":"Loft", "count": 1}
--     ]
--   },
--   {
--     "name": "Corpo 2 - Dependance",
--     "roomTypes": [
--       {"type":"doppia", "customLabel":"", "count": 3}
--     ]
--   }
-- ]
--
-- Il totale unità (somma di tutti i "count") viene usato al posto del
-- vecchio campo singolo "bedrooms" per il calcolo dell'ADR nel report,
-- quando questa sezione è compilata (vedi getAssetUnits() in
-- report-view.html e dossier-send.html). Se room_inventory è vuoto,
-- resta il fallback sul campo "Camere" (bedrooms).
-- =====================================================================

alter table public.opportunities
  add column if not exists room_inventory jsonb not null default '[]'::jsonb;

comment on column public.opportunities.room_inventory is 'Composizione camere/alloggi per corpo di fabbrica (array di edifici, ognuno con nome e tipologie di camere con relativo conteggio) — usato per il calcolo unità nell''ADR, con fallback sul campo bedrooms se vuoto';
