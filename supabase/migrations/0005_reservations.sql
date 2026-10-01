-- =============================================================================
-- 0005_reservations.sql
-- Reservas, ledger de números y comprobantes de pago.
-- La escritura la hacen exclusivamente las RPC de 0011 (los clientes no tienen
-- INSERT/UPDATE directo sobre reservations ni reservation_numbers).
-- =============================================================================

create table if not exists public.reservations (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete restrict,
  merchant_id uuid not null references public.merchants(id) on delete restrict,
  profile_id  uuid not null references public.profiles(id) on delete restrict,
  status      public.reservation_status not null default 'PENDING',

  number_count int not null,
  unit_price   numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  currency     char(3) not null default 'ARS',

  reserved_at          timestamptz not null default now(),
  expires_at           timestamptz not null,
  payment_submitted_at timestamptz,
  review_deadline_at   timestamptz,
  approved_at          timestamptz,
  closed_at            timestamptz,

  expiration_reason text,
  review_note       text,
  cancel_reason     text,
  rejection_count   int not null default 0,

  terms_acceptance_id uuid,   -- FK agregada en 0007 (terms_acceptances)

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint reservations_number_count_range check (number_count between 1 and 1000),
  constraint reservations_price_nonneg       check (unit_price >= 0 and total_amount >= 0),
  constraint reservations_currency_upper     check (currency = upper(currency)),
  constraint reservations_expiry_after_start check (expires_at > reserved_at),
  constraint reservations_total_matches
    check (total_amount = round(unit_price * number_count, 2)),
  constraint reservations_approved_check
    check ((status = 'APPROVED') = (approved_at is not null)),
  constraint reservations_terminal_closed_check
    check ((status in ('EXPIRED','REJECTED','CANCELLED')) = (closed_at is not null)),
  constraint reservations_submitted_check
    check ((status = 'PAYMENT_SUBMITTED') <= (payment_submitted_at is not null)),
  constraint reservations_rejection_count_nonneg check (rejection_count >= 0)
);

comment on table public.reservations is
  'Hold de 1..N numeros sobre un evento. Los precios se guardan como snapshot: si el comercio cambia el precio, la reserva vieja no se altera.';
comment on column public.reservations.expires_at is
  'Vencimiento del hold. Lo calcula la base desde el TTL efectivo, nunca el cliente.';
comment on column public.reservations.review_deadline_at is
  'Vencimiento de la REVISION (distinto del hold): si el comercio no revisa a tiempo, el participante no pierde los numeros.';

create index if not exists reservations_profile_idx   on public.reservations (profile_id, status);
create index if not exists reservations_event_idx     on public.reservations (event_id, status);
create index if not exists reservations_expiry_idx    on public.reservations (status, expires_at)
  where status in ('PENDING','PAYMENT_SUBMITTED');
create index if not exists reservations_merchant_idx  on public.reservations (merchant_id, status);
create index if not exists reservations_review_idx    on public.reservations (status, review_deadline_at)
  where status = 'PAYMENT_SUBMITTED';
-- Antiabuso: cuántas reservas vivas tiene un perfil.
create index if not exists reservations_open_idx       on public.reservations (profile_id, reserved_at)
  where status in ('PENDING','PAYMENT_SUBMITTED');
create index if not exists reservations_created_idx    on public.reservations (profile_id, created_at desc);

drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at
  before update on public.reservations
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- reservation_numbers: LEDGER histórico (append-only) de qué número estuvo en
-- qué reserva. event_numbers = presente; esto = historia. Ambos se escriben en
-- la MISMA transacción de la RPC, nunca por separado desde el cliente.
-- ---------------------------------------------------------------------------
create table if not exists public.reservation_numbers (
  id              uuid primary key default gen_random_uuid(),
  reservation_id  uuid not null references public.reservations(id) on delete restrict,
  event_number_id uuid not null references public.event_numbers(id) on delete restrict,
  event_id        uuid not null references public.events(id) on delete restrict,
  number          int not null,
  assigned_at     timestamptz not null default now(),
  released_at     timestamptz,
  release_reason  text
);

comment on table public.reservation_numbers is
  'Ledger append-only. released_at IS NULL = asignacion vigente. Permite responder quien tuvo el numero 25 y cuando, para siempre.';

-- Una sola asignación vigente por número y por evento.
create unique index if not exists reservation_numbers_active_uk
  on public.reservation_numbers (event_id, number) where released_at is null;
create index if not exists reservation_numbers_reservation_idx
  on public.reservation_numbers (reservation_id);
create index if not exists reservation_numbers_event_idx
  on public.reservation_numbers (event_id, number, assigned_at desc);

-- ---------------------------------------------------------------------------
-- payment_receipts: metadata del comprobante. El ARCHIVO vive en Storage
-- (bucket privado "receipts"), nunca en la base.
-- ---------------------------------------------------------------------------
create table if not exists public.payment_receipts (
  id             uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete restrict,
  merchant_id    uuid not null references public.merchants(id) on delete restrict,
  event_id       uuid not null references public.events(id) on delete restrict,
  uploaded_by    uuid not null references public.profiles(id) on delete restrict,

  storage_path  text not null,
  original_name text,
  mime_type     text not null,
  size_bytes    bigint not null,
  checksum_sha256 text,

  status        public.receipt_status not null default 'PENDING',
  review_reason text,
  reviewed_by   uuid references public.profiles(id) on delete set null,
  reviewed_at   timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint payment_receipts_size_range check (size_bytes between 1 and 8388608),
  constraint payment_receipts_mime_allowed check (
    mime_type in ('image/jpeg','image/png','image/webp','application/pdf')
  ),
  constraint payment_receipts_path_len check (char_length(storage_path) between 10 and 400),
  -- Nadie se autorrevisa.
  constraint payment_receipts_not_self_reviewed check (reviewed_by is distinct from uploaded_by),
  constraint payment_receipts_reviewed_check
    check ((status = 'PENDING') or (reviewed_by is not null and reviewed_at is not null))
);

comment on table public.payment_receipts is
  'Metadata del comprobante. El archivo vive en el bucket privado receipts; se accede por URL firmada con la sesion del usuario.';

-- Un solo comprobante en revisión por reserva: evita el spam de uploads.
create unique index if not exists payment_receipts_one_pending_uk
  on public.payment_receipts (reservation_id) where status = 'PENDING';
create index if not exists payment_receipts_reservation_idx on public.payment_receipts (reservation_id, created_at desc);
create index if not exists payment_receipts_merchant_idx    on public.payment_receipts (merchant_id, status);
create index if not exists payment_receipts_path_idx        on public.payment_receipts (storage_path);

drop trigger if exists payment_receipts_set_updated_at on public.payment_receipts;
create trigger payment_receipts_set_updated_at
  before update on public.payment_receipts
  for each row execute function private.set_updated_at();