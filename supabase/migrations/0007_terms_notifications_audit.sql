-- =============================================================================
-- 0007_terms_notifications_audit.sql
-- Legal (términos y aceptaciones), notificaciones, auditoría y bloqueos.
-- Incluye al final las FK diferidas de otros archivos.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- terms_versions: textos legales VERSIONADOS. No se sobrescribe un texto
-- publicado: se crea una versión nueva y se marca is_current.
-- ---------------------------------------------------------------------------
create table if not exists public.terms_versions (
  id           uuid primary key default gen_random_uuid(),
  scope        public.terms_scope not null,
  event_id     uuid references public.events(id) on delete restrict,
  kind         public.terms_kind not null,
  version      text not null,
  title        text not null,
  content      text not null,
  content_hash text not null,
  published_at timestamptz,
  is_current   boolean not null default true,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint terms_versions_scope_event_check
    check ((scope = 'EVENT') = (event_id is not null)),
  constraint terms_versions_version_format
    check (version ~ '^[0-9]+\.[0-9]+(-[a-z0-9]+)?$'),
  constraint terms_versions_hash_format
    check (content_hash ~ '^[0-9a-f]{64}$'),
  constraint terms_versions_content_len check (char_length(content) >= 50)
);

-- event_id es NULL en los documentos globales: en Postgres los NULL son
-- distintos entre sí, así que hacen falta índices parciales explícitos.
create unique index if not exists terms_versions_global_uk
  on public.terms_versions (kind, version) where scope = 'GLOBAL';
create unique index if not exists terms_versions_event_uk
  on public.terms_versions (event_id, kind, version) where scope = 'EVENT';
create unique index if not exists terms_versions_current_global_uk
  on public.terms_versions (kind) where is_current and scope = 'GLOBAL';
create unique index if not exists terms_versions_current_event_uk
  on public.terms_versions (event_id, kind) where is_current and scope = 'EVENT';

comment on table public.terms_versions is
  'Textos legales versionados. La version 1.0-draft del seed es una PLANTILLA: requiere revision legal antes de uso comercial.';

drop trigger if exists terms_versions_set_updated_at on public.terms_versions;
create trigger terms_versions_set_updated_at
  before update on public.terms_versions
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- terms_acceptances: EVIDENCIA de aceptación. Append-only por diseño.
-- ---------------------------------------------------------------------------
create table if not exists public.terms_acceptances (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles(id) on delete restrict,
  terms_version_id   uuid not null references public.terms_versions(id) on delete restrict,
  event_id           uuid references public.events(id) on delete restrict,
  reservation_id     uuid references public.reservations(id) on delete restrict,
  user_type          public.acceptance_user_type not null,
  accepted_at        timestamptz not null default now(),
  content_hash_snapshot text not null,
  source             text not null default 'WEB',
  ip_hash            text,
  user_agent_hash    text,

  constraint terms_acceptances_uk unique (profile_id, terms_version_id),
  constraint terms_acceptances_source_valid check (source in ('WEB','API')),
  constraint terms_acceptances_hash_format check (content_hash_snapshot ~ '^[0-9a-f]{64}$')
);

comment on table public.terms_acceptances is
  'Evidencia de aceptacion: quien, de que version exacta, cuando y con que hash. No se reescribe ni se borra.';

create index if not exists terms_acceptances_profile_idx on public.terms_acceptances (profile_id);
create index if not exists terms_acceptances_event_idx   on public.terms_acceptances (event_id);

-- ---------------------------------------------------------------------------
-- Guarda genérica de tablas append-only.
-- ---------------------------------------------------------------------------
create or replace function private.guard_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'APPEND_ONLY_TABLE'
    using errcode = '42501',
          detail  = format('La tabla %s es append-only: no admite %s.', tg_table_name, tg_op);
end $$;

drop trigger if exists terms_acceptances_append_only on public.terms_acceptances;
create trigger terms_acceptances_append_only
  before update or delete on public.terms_acceptances
  for each row execute function private.guard_append_only();

-- ---------------------------------------------------------------------------
-- notifications: bandeja interna Y outbox, en una sola tabla.
-- El jsonb "data" es payload de transporte, no dato relacional consultable.
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id                   uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete restrict,
  merchant_id          uuid references public.merchants(id) on delete restrict,
  event_id             uuid references public.events(id) on delete restrict,
  reservation_id       uuid references public.reservations(id) on delete restrict,

  type    text not null,
  channel public.notification_channel not null default 'INTERNAL',
  title   text not null,
  body    text,
  data    jsonb,

  status     public.notification_status not null default 'PENDING',
  attempts   int not null default 0,
  last_error text,

  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  read_at    timestamptz,

  constraint notifications_type_format check (type ~ '^[a-z0-9_.]+$'),
  constraint notifications_attempts_nonneg check (attempts >= 0),
  constraint notifications_read_check check ((status = 'READ') = (read_at is not null))
);

comment on table public.notifications is
  'Notificaciones internas + outbox para canales futuros. Los componentes React nunca conocen el proveedor.';

create index if not exists notifications_inbox_idx  on public.notifications (recipient_profile_id, read_at);
create index if not exists notifications_outbox_idx on public.notifications (status, channel, created_at)
  where status in ('PENDING','FAILED');
-- Idempotencia: una sola notificación del mismo tipo por reserva.
create unique index if not exists notifications_idempotency_uk
  on public.notifications (recipient_profile_id, type, reservation_id)
  where reservation_id is not null;

-- ---------------------------------------------------------------------------
-- audit_logs: append-only. Sin UPDATE ni DELETE, ni siquiera para el OWNER
-- (un log editable no es auditoría).
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id                  uuid primary key default gen_random_uuid(),
  actor_profile_id    uuid references public.profiles(id) on delete set null,
  actor_platform_role public.platform_role,
  actor_member_role   public.member_role,
  merchant_id         uuid references public.merchants(id) on delete restrict,
  event_id            uuid references public.events(id) on delete restrict,

  entity_type text not null,
  entity_id   uuid,
  action      text not null,
  before      jsonb,
  after       jsonb,
  metadata    jsonb,
  created_at  timestamptz not null default now(),

  constraint audit_logs_action_format check (action ~ '^[a-z0-9_.]+$'),
  constraint audit_logs_entity_type_len check (char_length(entity_type) between 2 and 60)
);

comment on table public.audit_logs is
  'Auditoria de lo que toca dinero, participacion, permisos o resultado. Se escribe en la MISMA transaccion de la operacion. Sin PII innecesaria (nunca IP cruda).';

create index if not exists audit_logs_merchant_idx on public.audit_logs (merchant_id, created_at desc);
create index if not exists audit_logs_event_idx    on public.audit_logs (event_id, created_at desc);
create index if not exists audit_logs_actor_idx    on public.audit_logs (actor_profile_id, created_at desc);
create index if not exists audit_logs_entity_idx   on public.audit_logs (entity_type, entity_id, created_at desc);
create index if not exists audit_logs_action_idx   on public.audit_logs (action, created_at desc);

drop trigger if exists audit_logs_append_only on public.audit_logs;
create trigger audit_logs_append_only
  before update or delete on public.audit_logs
  for each row execute function private.guard_append_only();

-- ---------------------------------------------------------------------------
-- security_blocks: bloqueos manuales y automáticos. Es también el seam
-- "abuse_control" para IP / CAPTCHA / fingerprint / reputación a futuro.
-- ---------------------------------------------------------------------------
create table if not exists public.security_blocks (
  id          uuid primary key default gen_random_uuid(),
  scope       text not null,
  merchant_id uuid references public.merchants(id) on delete restrict,
  event_id    uuid references public.events(id) on delete restrict,

  subject_profile_id uuid references public.profiles(id) on delete restrict,
  subject_key        text,

  reason     text not null,
  source     text not null default 'MANUAL',
  blocked_by uuid references public.profiles(id) on delete set null,

  starts_at     timestamptz not null default now(),
  blocked_until timestamptz,
  lifted_at     timestamptz,
  lift_reason   text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint security_blocks_scope_valid  check (scope in ('GLOBAL','MERCHANT','EVENT')),
  constraint security_blocks_source_valid check (source in ('AUTO_ABUSE','MANUAL','RATE_LIMIT')),
  constraint security_blocks_subject_required
    check (subject_profile_id is not null or subject_key is not null),
  constraint security_blocks_reason_len check (char_length(btrim(reason)) >= 5),
  -- Cada alcance exige las referencias que le corresponden (y sólo esas).
  constraint security_blocks_scope_refs check (
    (scope = 'GLOBAL'   and merchant_id is null     and event_id is null) or
    (scope = 'MERCHANT' and merchant_id is not null and event_id is null) or
    (scope = 'EVENT'    and merchant_id is not null and event_id is not null)
  ),
  constraint security_blocks_until_after_start
    check (blocked_until is null or blocked_until > starts_at),
  constraint security_blocks_lifted_check
    check ((lifted_at is not null) = (lift_reason is not null))
);

comment on table public.security_blocks is
  'Bloqueos por perfil o por clave. subject_key guarda SOLO un hash con salt, nunca la IP cruda. Retencion maxima 30 dias.';

create index if not exists security_blocks_profile_idx  on public.security_blocks (subject_profile_id, blocked_until);
create index if not exists security_blocks_key_idx      on public.security_blocks (subject_key, blocked_until);
create index if not exists security_blocks_merchant_idx on public.security_blocks (merchant_id, lifted_at);

drop trigger if exists security_blocks_set_updated_at on public.security_blocks;
create trigger security_blocks_set_updated_at
  before update on public.security_blocks
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- FK DIFERIDAS: van acá porque referencian tablas creadas en archivos
-- distintos. A esta altura ya existen todas las tablas.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'event_numbers_reservation_fk') then
    alter table public.event_numbers
      add constraint event_numbers_reservation_fk
      foreign key (reservation_id) references public.reservations(id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'events_terms_version_fk') then
    alter table public.events
      add constraint events_terms_version_fk
      foreign key (terms_version_id) references public.terms_versions(id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'reservations_terms_acceptance_fk') then
    alter table public.reservations
      add constraint reservations_terms_acceptance_fk
      foreign key (terms_acceptance_id) references public.terms_acceptances(id) on delete restrict;
  end if;
end $$;