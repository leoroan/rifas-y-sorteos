-- =============================================================================
-- 0017_merchant_invites.sql
-- Invitar staff por email aunque la persona todavía no esté registrada.
--
-- ¿Por qué esta tabla existe? merchant_members exige un profile_id real (FK a
-- auth.users), y desde el frontend NO se puede crear un usuario de Auth (eso
-- requiere service_role, que jamás llega al navegador). Entonces el OWNER no
-- puede "crear" al comerciante: puede INVITARLO. Cuando la persona se registre
-- con ese email, el trigger de alta activa la membresía automáticamente.
--
-- ADVERTENCIA DE SEGURIDAD: la activación es por coincidencia de email. Si el
-- proyecto tiene autoconfirm activado (sin verificar el email), cualquiera
-- podría registrar un email ajeno y quedarse con la invitación. Para uso real
-- conviene exigir confirmación de email (Authentication -> Providers -> Email).
-- =============================================================================

create table if not exists public.merchant_invites (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  email       text not null,
  role        public.member_role not null default 'COLLABORATOR',
  status      text not null default 'PENDING',
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at  timestamptz,

  constraint merchant_invites_status_valid check (status in ('PENDING','ACCEPTED','REVOKED')),
  constraint merchant_invites_email_format
    check (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
  -- Una invitación pendiente por comercio y email: re-invitar es idempotente.
  constraint merchant_invites_uk unique (merchant_id, email),
  -- Coherencia entre estado y sellos de tiempo.
  constraint merchant_invites_accepted_check
    check ((status = 'ACCEPTED') = (accepted_at is not null)),
  constraint merchant_invites_revoked_check
    check ((status = 'REVOKED') = (revoked_at is not null))
);

comment on table public.merchant_invites is
  'Invitaciones de staff por email. Se activan solas cuando la persona se registra.';

create index if not exists merchant_invites_email_idx
  on public.merchant_invites (lower(email), status) where status = 'PENDING';
create index if not exists merchant_invites_merchant_idx
  on public.merchant_invites (merchant_id, status);

alter table public.merchant_invites enable row level security;

-- El OWNER ve todas; el staff sólo las de su comercio.
drop policy if exists merchant_invites_select_scope on public.merchant_invites;
create policy merchant_invites_select_scope on public.merchant_invites
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(merchant_id));

-- Sin INSERT/UPDATE/DELETE directos: sólo por RPC auditada.
revoke all on public.merchant_invites from anon, authenticated;
grant select on public.merchant_invites to authenticated;

-- ---------------------------------------------------------------------------
-- INVITAR (OWNER o comerciante con staff.manage). Si el email ya está
-- registrado se puede asignar directo; si no, queda PENDING y se activa
-- sola cuando la persona se registre.
-- ---------------------------------------------------------------------------
create or replace function public.staff_invite(
  p_merchant_id uuid,
  p_email       text,
  p_role        public.member_role default 'COLLABORATOR'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_id    uuid;
  v_ya    boolean;
begin
  if not ((select private.is_owner())
          or private.has_merchant_permission(p_merchant_id, 'staff.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para invitar gente a este comercio.');
  end if;

  -- Un comerciante NO puede otorgar el rol MERCHANT. Sólo el OWNER.
  if p_role = 'MERCHANT' and not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede asignar el rol de comerciante.');
  end if;

  if v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_EMAIL',
      'message', 'El email no parece válido.');
  end if;

  -- ¿Ya es miembro activo?
  select exists (
    select 1
      from public.merchant_members mm
      join public.profiles p on p.id = mm.profile_id
     where mm.merchant_id = p_merchant_id
       and lower(p.email) = v_email
       and mm.status = 'ACTIVE'
  ) into v_ya;

  if v_ya then
    return jsonb_build_object('ok', false, 'code', 'ALREADY_MEMBER',
      'message', 'Ese email ya es parte del comercio.');
  end if;

  insert into public.merchant_invites (merchant_id, email, role, status, created_by)
  values (p_merchant_id, v_email, p_role, 'PENDING', (select auth.uid()))
  on conflict (merchant_id, email) do update
     set status      = 'PENDING',
         role        = excluded.role,
         accepted_at = null,
         revoked_at  = null,
         created_by  = excluded.created_by
  returning id into v_id;

  perform private.log_audit('staff.invite', 'merchant_invite', v_id, p_merchant_id, null,
    null, jsonb_build_object('email', v_email, 'role', p_role, 'status', 'PENDING'));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'invite_id', v_id, 'email', v_email, 'status', 'PENDING'));
end $$;

-- ---------------------------------------------------------------------------
-- REVOCAR una invitación pendiente.
-- ---------------------------------------------------------------------------
create or replace function public.staff_revoke_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_i public.merchant_invites;
begin
  select * into v_i from public.merchant_invites mi where mi.id = p_invite_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND',
      'message', 'La invitación no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_i.merchant_id, 'staff.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para revocar invitaciones de este comercio.');
  end if;

  if v_i.status <> 'PENDING' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Sólo se pueden revocar invitaciones pendientes.');
  end if;

  update public.merchant_invites mi
     set status = 'REVOKED', revoked_at = now()
   where mi.id = p_invite_id;

  perform private.log_audit('staff.revoke_invite', 'merchant_invite', p_invite_id,
    v_i.merchant_id, null,
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', 'REVOKED'));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('invite_id', p_invite_id));
end $$;

-- ---------------------------------------------------------------------------
-- Activación automática: al registrarse alguien cuyo email tiene invitación
-- pendiente, se crea la membresía y se marca la invitación como aceptada.
-- Se extiende handle_new_user (el trigger on_auth_user_created ya apunta acá).
-- ---------------------------------------------------------------------------
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

  -- Invitaciones pendientes para este email -> membresía automática.
  with aceptadas as (
    update public.merchant_invites mi
       set status = 'ACCEPTED', accepted_at = now()
     where lower(mi.email) = lower(new.email)
       and mi.status = 'PENDING'
    returning mi.merchant_id, mi.role
  )
  insert into public.merchant_members (merchant_id, profile_id, role, status)
  select a.merchant_id, new.id, a.role, 'ACTIVE'
    from aceptadas a
  on conflict (merchant_id, profile_id) do update
     set role = excluded.role, status = 'ACTIVE';

  -- Aviso al nuevo miembro.
  if exists (
    select 1 from public.merchant_members mm
     where mm.profile_id = new.id and mm.status = 'ACTIVE'
  ) then
    perform private.fn_notify(new.id, 'staff.added',
      'Te agregaron a un comercio',
      'Ya podés entrar al panel del comercio con tu cuenta.');
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------------------
-- GRANTS de las RPC nuevas.
-- ---------------------------------------------------------------------------
revoke all on function public.staff_invite(uuid, text, public.member_role) from public, anon;
revoke all on function public.staff_revoke_invite(uuid) from public, anon;
grant execute on function public.staff_invite(uuid, text, public.member_role) to authenticated;
grant execute on function public.staff_revoke_invite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Verificación: ninguna tabla sin RLS.
-- ---------------------------------------------------------------------------
do $$
declare
  v_missing text;
begin
  select string_agg(c.relname, ', ') into v_missing
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false;

  if v_missing is not null then
    raise exception 'RLS_MISSING_ON_TABLES'
      using detail = format('Tablas sin RLS: %s', v_missing);
  end if;
end $$;