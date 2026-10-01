-- =============================================================================
-- 0004_events.sql
-- Catálogo de fuentes de sorteo, eventos, premios y números.
-- NOTA: las FK a tablas que se crean más adelante (reservations, terms_versions)
-- se agregan al final de 0007_terms_notifications_audit.sql.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- draw_sources: catálogo flexible de loterías/medios de sorteo.
-- Es tabla y no enum porque las opciones NO son universales: el OWNER agrega
-- fuentes desde la configuración, sin migración de esquema.
-- ---------------------------------------------------------------------------
create table if not exists public.draw_sources (
  id           uuid primary key default gen_random_uuid(),
  code         text not null,
  name         text not null,
  kind         text not null check (kind in ('NATIONAL','PROVINCIAL','MUNICIPAL','PRIVATE','OTHER')),
  jurisdiction text,
  shifts       text[] not null default array['UNICA'],
  timezone     text not null default 'America/Argentina/Buenos_Aires',
  is_active    boolean not null default true,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint draw_sources_code_format check (code ~ '^[A-Z0-9_]{3,40}$')
);

create unique index if not exists draw_sources_code_uk on public.draw_sources (lower(code));
create index if not exists draw_sources_active_idx on public.draw_sources (is_active, sort_order);

-- ---------------------------------------------------------------------------
-- events: la entidad central. Un solo modelo para RAFFLE y DRAW.
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete restrict,

  kind        public.event_kind not null default 'RAFFLE',
  title       text not null,
  slug        text not null,
  description text,
  cover_path  text,
  status      public.event_status not null default 'DRAFT',

  starts_at             timestamptz not null default now(),
  participation_ends_at timestamptz not null,
  expected_draw_at      timestamptz,
  timezone              text not null default 'America/Argentina/Buenos_Aires',

  numbers_from      int not null,
  numbers_to        int not null,
  number_padding    smallint not null default 3,
  numbers_locked_at timestamptz,

  price_per_number numeric(12,2) not null default 0,
  currency         char(3) not null default 'ARS',

  max_numbers_registered     int not null default 10,
  max_numbers_anonymous      int not null default 3,
  reservation_ttl_registered interval not null default interval '24 hours',
  reservation_ttl_anonymous  interval not null default interval '2 hours',
  review_ttl                 interval not null default interval '72 hours',

  winner_method        text not null default 'RANDOM_SEEDED',
  winner_rule          text,
  draw_source_id       uuid references public.draw_sources(id) on delete restrict,
  draw_source_detail   text,
  draw_shift           text,
  draw_fallback_policy text not null default 'HOLD_FOR_REVIEW',

  legal_status        text not null default 'PENDING_REVIEW',
  legal_notes         text,
  legal_evidence_path text,

  terms_version_id uuid,

  published_at timestamptz,
  closed_at    timestamptz,
  drawn_at     timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,

  created_by uuid references public.profiles(id) on delete restrict,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint events_slug_format check (slug ~ '^[a-z0-9]([a-z0-9-]{1,58})[a-z0-9]$'),
  constraint events_title_len   check (char_length(title) between 3 and 140),
  constraint events_numbers_range check (numbers_from >= 1 and numbers_to >= numbers_from),
  constraint events_numbers_total check ((numbers_to - numbers_from + 1) between 1 and 5000),
  constraint events_padding_range check (number_padding between 1 and 6),
  constraint events_price_nonneg  check (price_per_number >= 0),
  constraint events_currency_upper check (currency = upper(currency)),
  constraint events_max_registered check (max_numbers_registered between 1 and 1000),
  constraint events_max_anonymous  check (max_numbers_anonymous between 1 and 1000),
  constraint events_ttl_registered check (reservation_ttl_registered between interval '5 minutes' and interval '30 days'),
  constraint events_ttl_anonymous  check (reservation_ttl_anonymous  between interval '5 minutes' and interval '30 days'),
  constraint events_review_ttl     check (review_ttl between interval '1 hour' and interval '30 days'),
  constraint events_window_order   check (participation_ends_at > starts_at),
  constraint events_draw_after_end check (expected_draw_at is null or expected_draw_at >= participation_ends_at),
  constraint events_winner_method_valid
    check (winner_method in ('MANUAL','RANDOM_SEEDED','EXTERNAL_LOTTERY')),
  constraint events_winner_rule_valid
    check (winner_rule is null or winner_rule in ('MODULO_RESTO','EXTRACTO_EXACTO','ULTIMOS_DIGITOS')),
  constraint events_winner_rule_required
    check (winner_method <> 'EXTERNAL_LOTTERY' or winner_rule is not null),
  constraint events_fallback_valid
    check (draw_fallback_policy in ('HOLD_FOR_REVIEW','RESORT_NEXT_DRAW','CANCEL_EVENT')),
  constraint events_legal_status_valid
    check (legal_status in ('PENDING_REVIEW','AUTHORIZED','NOT_AUTHORIZED','EXEMPT','CANCELLED')),
  constraint events_numbers_locked_only_after_publish
    check (numbers_locked_at is null or status <> 'DRAFT')
);

comment on column public.events.numbers_locked_at is
  'Sello de inmutabilidad del rango de numeros. Se fija al publicar y no se puede volver atras.';
comment on column public.events.winner_method is
  'MANUAL: lo define el comerciante. RANDOM_SEEDED: sorteo aleatorio propio con seed verificable. EXTERNAL_LOTTERY: extracto de una loteria.';
comment on column public.events.legal_notes is
  'Jurisdiccion, numero de expediente, etc. El sistema registra, no opina sobre legalidad.';

create unique index if not exists events_slug_uk on public.events (lower(slug));
create index if not exists events_merchant_idx   on public.events (merchant_id, status);
create index if not exists events_public_idx     on public.events (status, participation_ends_at)
  where status in ('PUBLISHED','OPEN');
create index if not exists events_draw_source_idx on public.events (draw_source_id);
create index if not exists events_terms_idx      on public.events (terms_version_id);

-- ---------------------------------------------------------------------------
-- Guardas del evento
-- ---------------------------------------------------------------------------

-- 1) Inmutabilidad del rango de números. Una vez publicado (o con reservas),
--    nadie cambia la cantidad de números: ni la UI, ni la API, ni el SQL.
create or replace function private.guard_event_numbers_immutability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.numbers_locked_at is not null then
    if new.numbers_from   is distinct from old.numbers_from
       or new.numbers_to        is distinct from old.numbers_to
       or new.number_padding    is distinct from old.number_padding
       or new.kind              is distinct from old.kind
       or new.numbers_locked_at is distinct from old.numbers_locked_at then
      raise exception 'NUMBERS_LOCKED'
        using errcode = '23514',
              detail  = 'El rango y la cantidad de numeros no pueden modificarse una vez publicado el evento.';
    end if;
  end if;
  return new;
end $$;

-- 2) Las condiciones del evento no cambian una vez que salió de borrador.
create or replace function private.guard_event_terms_immutability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'DRAFT' then
    if new.terms_version_id is distinct from old.terms_version_id then
      raise exception 'TERMS_LOCKED'
        using errcode = '23514',
              detail  = 'Las condiciones del evento no se modifican una vez publicado.';
    end if;
  end if;
  return new;
end $$;

-- 3) Transiciones de estado válidas, con sellos de tiempo coherentes.
create or replace function private.guard_event_status_transitions()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_ok boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  v_ok := case old.status
            when 'DRAFT'     then new.status in ('PUBLISHED','CANCELLED')
            when 'PUBLISHED' then new.status in ('OPEN','CLOSED','CANCELLED')
            when 'OPEN'      then new.status in ('CLOSED','CANCELLED')
            when 'CLOSED'    then new.status in ('DRAWN','CANCELLED')
            else false
          end;

  if not v_ok then
    raise exception 'INVALID_EVENT_TRANSITION'
      using errcode = '23514',
            detail  = format('Transicion no permitida: %s -> %s', old.status, new.status);
  end if;

  if new.status = 'PUBLISHED' then new.published_at := coalesce(new.published_at, now()); end if;
  if new.status = 'CLOSED'    then new.closed_at    := coalesce(new.closed_at, now());    end if;
  if new.status = 'DRAWN'     then new.drawn_at     := coalesce(new.drawn_at, now());     end if;

  if new.status = 'CANCELLED' then
    if new.cancellation_reason is null or char_length(btrim(new.cancellation_reason)) < 5 then
      raise exception 'CANCELLATION_REASON_REQUIRED'
        using errcode = '23514',
              detail  = 'Cancelar un evento requiere un motivo de al menos 5 caracteres.';
    end if;
    new.cancelled_at := coalesce(new.cancelled_at, now());
  end if;

  return new;
end $$;

drop trigger if exists events_guard_numbers on public.events;
create trigger events_guard_numbers
  before update on public.events
  for each row execute function private.guard_event_numbers_immutability();

drop trigger if exists events_guard_terms on public.events;
create trigger events_guard_terms
  before update on public.events
  for each row execute function private.guard_event_terms_immutability();

drop trigger if exists events_guard_status on public.events;
create trigger events_guard_status
  before update on public.events
  for each row execute function private.guard_event_status_transitions();

drop trigger if exists events_guard_timezone on public.events;
create trigger events_guard_timezone
  before insert or update on public.events
  for each row execute function private.guard_timezone();

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at
  before update on public.events
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- prizes: entidad propia, N por evento.
-- ---------------------------------------------------------------------------
create table if not exists public.prizes (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references public.events(id) on delete cascade,
  position        int not null,
  title           text not null,
  description     text,
  image_path      text,
  estimated_value numeric(12,2),
  currency        char(3),
  conditions      text,
  status          text not null default 'ACTIVE',
  delivered_at    timestamptz,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint prizes_position_range check (position between 1 and 100),
  constraint prizes_title_len      check (char_length(title) between 2 and 160),
  constraint prizes_value_nonneg   check (estimated_value is null or estimated_value >= 0),
  constraint prizes_status_valid   check (status in ('ACTIVE','DELIVERED','CANCELLED')),
  constraint prizes_delivered_check check ((status = 'DELIVERED') = (delivered_at is not null)),
  constraint prizes_event_position_uk unique (event_id, position)
);

create index if not exists prizes_event_idx on public.prizes (event_id, position);

drop trigger if exists prizes_set_updated_at on public.prizes;
create trigger prizes_set_updated_at
  before update on public.prizes
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- event_numbers: una fila por número. Es el ESTADO ACTUAL y el punto donde se
-- serializa la concurrencia (ver §7.4: el CAS es un UPDATE condicional).
-- ---------------------------------------------------------------------------
create table if not exists public.event_numbers (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.events(id) on delete cascade,
  number         int not null,
  display_code   text not null,
  status         public.number_status not null default 'AVAILABLE',
  reservation_id uuid,   -- FK agregada en 0007 (reservations se crea después)
  updated_at     timestamptz not null default now(),

  constraint event_numbers_number_positive check (number >= 1),
  constraint event_numbers_uk unique (event_id, number),
  -- Invariante explícita: AVAILABLE <=> sin tenedor. No se confía al código.
  constraint event_numbers_status_reservation_check
    check ((status = 'AVAILABLE') = (reservation_id is null)),
  constraint event_numbers_display_code_check check (char_length(display_code) between 1 and 8)
);

-- Segunda red de seguridad, independiente del CAS: un número no puede
-- pertenecer a dos reservas a la vez.
create unique index if not exists event_numbers_reservation_uk
  on public.event_numbers (event_id, reservation_id) where reservation_id is not null;

create index if not exists event_numbers_event_status_idx on public.event_numbers (event_id, status);
create index if not exists event_numbers_reservation_idx  on public.event_numbers (reservation_id)
  where reservation_id is not null;

comment on table public.event_numbers is
  'Estado actual de cada numero. La verdad sobre disponibilidad vive aca, no en el grid del navegador.';

-- El número debe caer dentro del rango declarado en el evento.
create or replace function private.guard_event_number_range()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.events e
     where e.id = new.event_id
       and new.number between e.numbers_from and e.numbers_to
  ) then
    raise exception 'NUMBER_OUT_OF_RANGE'
      using errcode = '23514',
            detail  = format('El numero %s esta fuera del rango declarado del evento.', new.number);
  end if;
  return new;
end $$;

drop trigger if exists event_numbers_guard_range on public.event_numbers;
create trigger event_numbers_guard_range
  before insert or update of number, event_id on public.event_numbers
  for each row execute function private.guard_event_number_range();

drop trigger if exists event_numbers_set_updated_at on public.event_numbers;
create trigger event_numbers_set_updated_at
  before update on public.event_numbers
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Materializa los números del evento. Se llama SÓLO desde event_publish.
-- Idempotente: si ya existen, no hace nada.
-- ---------------------------------------------------------------------------
create or replace function private.fn_materialize_event_numbers(
  p_event_id uuid,
  p_from int,
  p_to int,
  p_padding int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted int;
begin
  insert into public.event_numbers (event_id, number, display_code, status)
  select p_event_id,
         g,
         lpad(g::text, greatest(p_padding, char_length(g::text)), '0'),
         'AVAILABLE'
    from generate_series(p_from, p_to) as g
  on conflict (event_id, number) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end $$;