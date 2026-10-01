-- =============================================================================
-- 0003_settings.sql
-- Configuración en dos niveles: global (OWNER) y por comercio (MERCHANT).
-- La regla dura: el comercio NUNCA puede aflojar una regla global (§12).
-- =============================================================================

create table if not exists public.system_settings (
  key         text primary key,
  value       jsonb not null,
  value_type  text not null check (value_type in ('int','numeric','bool','text','interval','json')),
  direction   text not null default 'none' check (direction in ('ceiling','floor','none')),
  min_value   numeric,
  max_value   numeric,
  description text not null,
  is_public   boolean not null default false,
  is_owner_only boolean not null default true,
  editable_by_merchant boolean not null default false,
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  constraint system_settings_key_format check (key ~ '^[a-z0-9_.]+$')
);

comment on table public.system_settings is
  'Configuracion global del producto. Define los TECHOS que un comercio no puede superar.';
comment on column public.system_settings.direction is
  'ceiling: el comercio puede bajar el valor, nunca subirlo. floor: al reves. none: sin techo global.';
comment on column public.system_settings.is_public is
  'Si true, un visitante anonimo puede leerla (p.ej. limites de participantes que la pagina publica muestra).';

create table if not exists public.merchant_settings (
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  key         text not null references public.system_settings(key) on delete restrict,
  value       jsonb not null,
  updated_by  uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (merchant_id, key)
);

comment on table public.merchant_settings is
  'Overrides por comercio. La validacion contra el techo global la hace merchant_set_setting + fn_effective_setting.';

create index if not exists system_settings_public_idx on public.system_settings (is_public) where is_public = true;
create index if not exists merchant_settings_key_idx   on public.merchant_settings (key);

-- ---------------------------------------------------------------------------
-- Valor efectivo = el del comercio acotado por el techo global.
-- Único lugar donde se resuelve la cascada. Ninguna policy ni RPC la reimplementa.
-- ---------------------------------------------------------------------------
create or replace function private.fn_effective_setting(p_merchant_id uuid, p_key text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    -- sin override del comercio: rige el global
    when ms.value is null then ss.value
    -- el comercio manda, pero acotado por el sentido declarado del techo
    when ss.direction = 'ceiling' and (ms.value)::numeric > (ss.value)::numeric then ss.value
    when ss.direction = 'floor'   and (ms.value)::numeric < (ss.value)::numeric then ss.value
    else ms.value
  end
  from public.system_settings ss
  left join public.merchant_settings ms
         on ms.key = ss.key and ms.merchant_id = p_merchant_id
  where ss.key = p_key;
$$;

comment on function private.fn_effective_setting(uuid, text) is
  'Resuelve global + override del comercio con techo. Los tipos que no son numericos usan el valor del comercio o el global tal cual.';

-- ---------------------------------------------------------------------------
-- Solo el OWNER (o service_role) crea/cambia claves globales.
-- ---------------------------------------------------------------------------
create or replace function private.guard_system_settings()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'SYSTEM_SETTINGS_OWNER_ONLY'
      using errcode = '42501',
            detail  = 'La configuracion global solo se modifica por admin_set_system_setting.';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;

drop trigger if exists system_settings_guard on public.system_settings;
create trigger system_settings_guard
  before insert or update or delete on public.system_settings
  for each row execute function private.guard_system_settings();

drop trigger if exists system_settings_set_updated_at on public.system_settings;
create trigger system_settings_set_updated_at
  before update on public.system_settings
  for each row execute function private.set_updated_at();