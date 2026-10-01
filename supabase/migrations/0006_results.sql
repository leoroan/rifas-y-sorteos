-- =============================================================================
-- 0006_results.sql
-- Resultado del sorteo y ganadores publicados.
-- draw_results guarda TODO lo necesario para reproducir y auditar el resultado.
-- =============================================================================

create table if not exists public.draw_results (
  id      uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,

  -- Fuente usada, con snapshot: si mañana se edita el catálogo, el resultado
  -- histórico sigue siendo explicable.
  draw_source_id       uuid references public.draw_sources(id) on delete restrict,
  draw_source_snapshot text,
  draw_shift           text,
  draw_date            date,

  extract_number int,
  raw_payload    jsonb,

  -- Snapshot del mecanismo y del rango vigente al momento del sorteo.
  winner_method_snapshot  text not null,
  winner_rule_snapshot    text,
  numbers_from_snapshot   int not null,
  numbers_to_snapshot     int not null,
  total_numbers_snapshot  int not null,

  -- Sorteo aleatorio propio: seed del servidor y derivación verificable.
  seed            text,
  algorithm       text,
  seed_commitment text,
  revealed_at     timestamptz,

  computed_number int,
  justification   text,
  evidence_url    text,
  evidence_path   text,
  notes           text,

  recorded_by uuid not null references public.profiles(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- UN SOLO resultado por evento: esto es lo que hace imposible reintentar el
  -- sorteo hasta obtener un ganador conveniente.
  constraint draw_results_event_uk unique (event_id),

  constraint draw_results_method_valid
    check (winner_method_snapshot in ('MANUAL','RANDOM_SEEDED','EXTERNAL_LOTTERY')),
  constraint draw_results_range_valid
    check (numbers_to_snapshot >= numbers_from_snapshot and total_numbers_snapshot >= 1),
  constraint draw_results_computed_in_range
    check (computed_number is null
           or computed_number between numbers_from_snapshot and numbers_to_snapshot),

  -- MANUAL: exige justificación y evidencia.
  constraint draw_results_manual_requires_justification
    check (winner_method_snapshot <> 'MANUAL'
           or (justification is not null and char_length(btrim(justification)) >= 20)),
  constraint draw_results_manual_requires_evidence
    check (winner_method_snapshot <> 'MANUAL'
           or evidence_path is not null or evidence_url is not null),

  -- RANDOM_SEEDED: seed + algoritmo obligatorios.
  constraint draw_results_seeded_requires_seed
    check (winner_method_snapshot <> 'RANDOM_SEEDED'
           or (seed is not null and algorithm is not null)),

  -- EXTERNAL_LOTTERY: extracto, fecha y regla obligatorios.
  constraint draw_results_external_requires_data
    check (winner_method_snapshot <> 'EXTERNAL_LOTTERY'
           or (extract_number is not null and draw_date is not null)),
  constraint draw_results_external_requires_rule
    check (winner_method_snapshot <> 'EXTERNAL_LOTTERY' or winner_rule_snapshot is not null),

  constraint draw_results_commitment_format
    check (seed_commitment is null or seed_commitment ~ '^[0-9a-f]{64}$')
);

comment on table public.draw_results is
  'Hecho del sorteo, reproducible. Inmutable para clientes (sin UPDATE/DELETE): un solo tiro, auditado.';
comment on column public.draw_results.seed is
  'Seed generado por el SERVIDOR (nunca aportado por el cliente). Con algorithm y snapshots permite recalcular el ganador.';

create index if not exists draw_results_recorded_idx on public.draw_results (recorded_at desc);
create index if not exists draw_results_source_idx   on public.draw_results (draw_source_id);

drop trigger if exists draw_results_set_updated_at on public.draw_results;
create trigger draw_results_set_updated_at
  before update on public.draw_results
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- event_winners: resultado publicado, uno por premio.
-- Se separa de draw_results porque UN sorteo puede adjudicar VARIOS premios.
-- ---------------------------------------------------------------------------
create table if not exists public.event_winners (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.events(id) on delete restrict,
  prize_id       uuid not null references public.prizes(id) on delete restrict,
  draw_result_id uuid not null references public.draw_results(id) on delete restrict,

  profile_id      uuid not null references public.profiles(id) on delete restrict,
  reservation_id  uuid not null references public.reservations(id) on delete restrict,
  event_number_id uuid not null references public.event_numbers(id) on delete restrict,
  number          int not null,
  position        int not null,

  published_at      timestamptz not null default now(),
  notified_at       timestamptz,
  claim_deadline_at timestamptz,
  claim_status      text not null default 'PENDING',
  notes             text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint event_winners_uk unique (event_id, prize_id),
  constraint event_winners_position_range check (position between 1 and 100),
  constraint event_winners_claim_status_valid
    check (claim_status in ('PENDING','CLAIMED','EXPIRED','DELIVERED'))
);

comment on table public.event_winners is
  'Ganador por premio. Un ganador bloqueado IGUAL gana: el bloqueo impide nuevas reservas, no revoca resultados.';

create index if not exists event_winners_profile_idx on public.event_winners (profile_id);
create index if not exists event_winners_event_idx   on public.event_winners (event_id);
create index if not exists event_winners_claim_idx   on public.event_winners (claim_status, claim_deadline_at);

drop trigger if exists event_winners_set_updated_at on public.event_winners;
create trigger event_winners_set_updated_at
  before update on public.event_winners
  for each row execute function private.set_updated_at();