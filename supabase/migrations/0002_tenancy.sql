-- =============================================================================
-- 0002_tenancy.sql
-- Identidad (profiles) y multi-tenancy (merchants, merchant_members) + RBAC.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- profiles: espejo 1:1 de auth.users. Es la tabla que consultan TODAS las
-- policies para saber quién es quién (nunca el JWT: ver §9.2 del documento).
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete restrict,
  display_name   text,
  email          text,
  phone          text,
  is_anonymous   boolean not null default true,
  converted_at   timestamptz,
  platform_role  public.platform_role not null default 'USER',
  status         public.profile_status not null default 'ACTIVE',
  anonymized_at  timestamptz,
  last_seen_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint profiles_display_name_len check (display_name is null or char_length(display_name) between 2 and 80),
  constraint profiles_email_len        check (email is null or char_length(email) <= 254),
  constraint profiles_anonymized_check check ((status = 'ANONYMIZED') = (anonymized_at is not null))
);

comment on table public.profiles is
  'Perfil de usuario. id = auth.users.id. La anonimizacion reemplaza PII y marca status=ANONYMIZED (no se borra: rompe auditoria y resultados).';
comment on column public.profiles.platform_role is
  'OWNER solo se asigna por migracion/seed o service_role. Inmutable desde la API (trigger guard_profile_privileges).';
comment on column public.profiles.is_anonymous is
  'Snapshot para reportes y limites. La fuente de verdad es auth.users.is_anonymous / el claim.';

create index if not exists profiles_platform_role_idx
  on public.profiles (platform_role) where platform_role = 'OWNER';
create index if not exists profiles_anon_retention_idx
  on public.profiles (last_seen_at) where is_anonymous = true;

-- Alta automática del perfil cuando se crea el usuario en Auth.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_anon boolean := coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false);
begin
  insert into public.profiles (id, email, display_name, is_anonymous)
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), ''),
    v_is_anon
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Mantiene profiles sincronizado con Auth (email e is_anonymous) y registra
-- la conversión de anónimo a registrado. No dispara en cada refresh de token.
create or replace function private.sync_profile_from_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new_anon boolean := coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false);
  v_old_anon boolean := coalesce((to_jsonb(old) ->> 'is_anonymous')::boolean, false);
begin
  if new.email is distinct from old.email or v_new_anon is distinct from v_old_anon then
    update public.profiles p
       set email        = new.email,
           is_anonymous = v_new_anon,
           converted_at = case when v_old_anon and not v_new_anon then now() else p.converted_at end,
           updated_at   = now()
     where p.id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update on auth.users
  for each row execute function private.sync_profile_from_auth();

-- El rol de plataforma y la anonimización NO se cambian desde la API.
-- Función con privilegios del invocador: por eso current_user es el rol real
-- del llamador ('authenticated', 'postgres' desde el SQL Editor, 'service_role').
create or replace function private.guard_profile_privileges()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.platform_role is distinct from old.platform_role
     and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'PLATFORM_ROLE_IMMUTABLE'
      using errcode = '42501',
            detail  = 'El rol de plataforma solo puede cambiarse desde una función privilegiada.';
  end if;

  if new.status is distinct from old.status
     and new.status in ('SUSPENDED', 'ANONYMIZED')
     and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'PROFILE_STATUS_PROTECTED'
      using errcode = '42501',
            detail  = 'Suspender o anonimizar un perfil requiere una operación privilegiada.';
  end if;

  return new;
end $$;

drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges
  before update on public.profiles
  for each row execute function private.guard_profile_privileges();

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- merchants: el comercio / tenant.
-- ---------------------------------------------------------------------------
create table if not exists public.merchants (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  slug              text not null,
  description       text,
  logo_path         text,
  contact_phone     text,
  contact_whatsapp  text,
  contact_instagram text,
  payment_instructions text,
  timezone          text not null default 'America/Argentina/Buenos_Aires',
  currency          char(3) not null default 'ARS',
  status            public.merchant_status not null default 'ACTIVE',
  legal_name        text,
  tax_id            text,
  created_by        uuid references public.profiles(id) on delete restrict,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint merchants_slug_format check (slug ~ '^[a-z0-9]([a-z0-9-]{1,38})[a-z0-9]$'),
  constraint merchants_name_len    check (char_length(name) between 2 and 120),
  constraint merchants_currency_upper check (currency = upper(currency))
);

create unique index if not exists merchants_slug_uk on public.merchants (lower(slug));
create index if not exists merchants_status_idx     on public.merchants (status);
create index if not exists merchants_created_by_idx on public.merchants (created_by);

-- Valida timezone contra el catálogo de PostgreSQL. No puede hacerse con CHECK
-- porque necesita una consulta.
create or replace function private.guard_timezone()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.timezone is not null
     and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = new.timezone) then
    raise exception 'INVALID_TIMEZONE'
      using errcode = '22023',
            detail  = format('Timezone desconocida: %s', new.timezone);
  end if;
  return new;
end $$;

drop trigger if exists merchants_guard_timezone on public.merchants;
create trigger merchants_guard_timezone
  before insert or update on public.merchants
  for each row execute function private.guard_timezone();

drop trigger if exists merchants_set_updated_at on public.merchants;
create trigger merchants_set_updated_at
  before update on public.merchants
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- merchant_members: staff del comercio (MERCHANT o COLLABORATOR).
-- El rol OWNER NO vive acá: es ortogonal (profiles.platform_role).
-- ---------------------------------------------------------------------------
create table if not exists public.merchant_members (
  id           uuid primary key default gen_random_uuid(),
  merchant_id  uuid not null references public.merchants(id) on delete restrict,
  profile_id   uuid not null references public.profiles(id) on delete restrict,
  role         public.member_role not null,
  status       public.member_status not null default 'ACTIVE',
  invited_by   uuid references public.profiles(id) on delete set null,
  joined_at    timestamptz not null default now(),
  suspended_at timestamptz,
  removed_at   timestamptz,
  revoke_after timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint merchant_members_uk unique (merchant_id, profile_id),
  constraint merchant_members_removed_check   check ((status = 'REMOVED')   = (removed_at is not null)),
  constraint merchant_members_suspended_check check ((status = 'SUSPENDED') = (suspended_at is not null))
);

comment on column public.merchant_members.revoke_after is
  'Un miembro REMOVED sigue bloqueado para participar en el comercio hasta esta fecha. NULL = sin ventana de gracia.';

create index if not exists merchant_members_profile_idx  on public.merchant_members (profile_id, status);
create index if not exists merchant_members_merchant_idx on public.merchant_members (merchant_id, status, role);

drop trigger if exists merchant_members_set_updated_at on public.merchant_members;
create trigger merchant_members_set_updated_at
  before update on public.merchant_members
-- ---------------------------------------------------------------------------
-- RBAC: catálogo de roles, permisos y su matriz por defecto.
-- Son datos semilla (0015_seed.sql), no configurables por clientes.
-- ---------------------------------------------------------------------------
create table if not exists public.roles (
  code       text primary key,
  label      text not null,
  scope      text not null check (scope in ('PLATFORM','MERCHANT')),
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  code        text primary key,
  description text not null,
  scope       text not null check (scope in ('PLATFORM','MERCHANT','EVENT')),
  created_at  timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_code       text not null references public.roles(code) on delete restrict,
  permission_code text not null references public.permissions(code) on delete restrict,
  created_at      timestamptz not null default now(),
  primary key (role_code, permission_code)
);

create table if not exists public.member_permissions (
  merchant_member_id uuid not null references public.merchant_members(id) on delete cascade,
  permission_code    text not null references public.permissions(code) on delete restrict,
  granted            boolean not null,
  granted_by         uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  primary key (merchant_member_id, permission_code)
);

comment on table public.member_permissions is
  'Overrides por colaborador. granted=false quita un permiso del rol; granted=true solo puede sumar permisos que el rol MERCHANT ya tenga (validado en staff_set_permission).';

create index if not exists member_permissions_code_idx on public.member_permissions (permission_code);
create index if not exists role_permissions_perm_idx   on public.role_permissions (permission_code);
  for each row execute function private.set_updated_at();