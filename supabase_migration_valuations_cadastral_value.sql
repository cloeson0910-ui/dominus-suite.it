-- Valore catastale (dato fiscale) + andamento storico prezzi di mercato (Eurostat)
-- per le valutazioni immobiliari (immonova_property_valuations).

alter table public.immonova_property_valuations
  add column if not exists cadastral_is_prima_casa boolean not null default false,
  add column if not exists cadastral_value numeric,
  add column if not exists cadastral_multiplier numeric,
  add column if not exists price_index_trend jsonb;

comment on column public.immonova_property_valuations.cadastral_is_prima_casa is 'Se true, applica il moltiplicatore catastale agevolato "prima casa" (110 invece di 120) per le categorie A escluso A/10 e C escluso C/1';
comment on column public.immonova_property_valuations.cadastral_value is 'Valore catastale calcolato: rendita catastale rivalutata del 5% moltiplicata per il coefficiente della categoria catastale (D.L. 262/2006, art. 2 c. 45) — dato fiscale, distinto dal valore di mercato';
comment on column public.immonova_property_valuations.cadastral_multiplier is 'Moltiplicatore catastale applicato nel calcolo di cadastral_value, salvato per trasparenza/tracciabilità nel documento finale';
comment on column public.immonova_property_valuations.price_index_trend is 'Andamento storico indice prezzi immobiliari (Eurostat prc_hpi_a, copertura a livello paese) — usato per il grafico di trend 5/10 anni nella relazione di valutazione, null se il paese non è coperto dal dataset';
