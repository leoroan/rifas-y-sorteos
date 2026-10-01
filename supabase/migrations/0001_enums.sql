-- =============================================================================
-- 0001_enums.sql
-- Esquemas base, extensiones, enums del dominio y trigger de updated_at.
-- Idempotente: se puede volver a ejecutar sin romper nada.
-- =============================================================================

-- Esquema de helpers de autorización. A propósito NO está en los esquemas
-- expuestos por PostgREST (db-schemas = public, graphql_public), así que sus
-- funciones no son invocables desde la API aunque se conozca su nombre.
create schema if not exists private;
comment on schema private is
  'Helpers de autorizacion (RLS/RPC). No expuesto a la API. Todas las funciones: security definer + search_path fijo.';

-- Supabase instala pgcrypto en el esquema "extensions". Lo aseguramos por si no está.
create schema if not exists extensions;
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pgcrypto') then
    create extension pgcrypto with schema extensions;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Helper temporal para crear enums de forma idempotente. Se elimina al final.
-- ---------------------------------------------------------------------------
create or replace function private.ensure_enum(p_name text, p_labels text[])
returns void
language plpgsql
as $$
declare
  v_labels text;
begin
  if exists (
    select 1 from pg_type t
      join pg_namespace n on n.oid = t.typnamespace
     where t.typname = p_name and n.nspname = 'public'
  ) then
    return;
  end if;

  select string_agg(quote_literal(l), ', ' order by ord)
    into v_labels
    from unnest(p_labels) with ordinality as u(l, ord);

  execute format('create type public.%I as enum (%s)', p_name, v_labels);
end $$;

-- ---------------------------------------------------------------------------
-- Enums del dominio
-- ---------------------------------------------------------------------------
select private.ensure_enum('platform_role',        array['OWNER','USER']);
select private.ensure_enum('profile_status',       array['ACTIVE','SUSPENDED','ANONYMIZED']);
select private.ensure_enum('merchant_status',      array['ACTIVE','SUSPENDED','CLOSED']);
select private.ensure_enum('member_role',          array['MERCHANT','COLLABORATOR']);
select private.ensure_enum('member_status',        array['ACTIVE','SUSPENDED','REMOVED']);
select private.ensure_enum('event_kind',           array['RAFFLE','DRAW']);
select private.ensure_enum('event_status',         array['DRAFT','PUBLISHED','OPEN','CLOSED','DRAWN','CANCELLED']);
select private.ensure_enum('number_status',        array['AVAILABLE','RESERVED','PAYMENT_SUBMITTED','PAID','CANCELLED','WINNER']);
select private.ensure_enum('reservation_status',   array['PENDING','PAYMENT_SUBMITTED','APPROVED','EXPIRED','REJECTED','CANCELLED']);
select private.ensure_enum('receipt_status',       array['PENDING','APPROVED','REJECTED']);
select private.ensure_enum('notification_channel', array['INTERNAL','EMAIL','WHATSAPP','TELEGRAM','PUSH']);
select private.ensure_enum('notification_status',  array['PENDING','SENT','READ','FAILED','SKIPPED']);
select private.ensure_enum('terms_scope',          array['GLOBAL','EVENT']);
select private.ensure_enum('terms_kind',           array['TERMS','PRIVACY','PARTICIPATION_RULES','EVENT_TERMS']);
select private.ensure_enum('acceptance_user_type', array['ANONYMOUS','REGISTERED']);

drop function private.ensure_enum(text, text[]);

-- ---------------------------------------------------------------------------
-- Trigger genérico de updated_at
-- Vive en "private" para no contaminar el esquema expuesto.
-- ---------------------------------------------------------------------------
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Las tablas con trigger de updated_at necesitan que el rol que escribe pueda
-- ejecutar esta función.
grant execute on function private.set_updated_at() to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- Verificación rápida
-- ---------------------------------------------------------------------------
-- select count(*) from pg_type t join pg_namespace n on n.oid = t.typnamespace
--  where n.nspname = 'public' and t.typtype = 'e';   -- esperado: 15