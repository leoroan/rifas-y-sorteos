-- =============================================================================
-- 0013_rpc_admin.sql
-- OWNER (plataforma), staff del comercio, configuración y bloqueos.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- COMERCIOS (sólo OWNER)
-- ---------------------------------------------------------------------------
create or replace function public.admin_merchant_create(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_name text := nullif(btrim(coalesce(p_payload->>'name','')), '');
  v_slug text := nullif(lower(btrim(coalesce(p_payload->>'slug',''))), '');
  v_id   uuid;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede crear comercios.');
  end if;

  if v_name is null or v_slug is null then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT',
      'message', 'Faltan el nombre o el identificador del comercio.');
  end if;

  insert into public.merchants (
    name, slug, description, logo_path, contact_phone, contact_whatsapp,
    contact_instagram, payment_instructions, timezone, currency,
    legal_name, tax_id, created_by
  ) values (
    v_name, v_slug,
    p_payload->>'description', p_payload->>'logo_path',
    p_payload->>'contact_phone', p_payload->>'contact_whatsapp',
    p_payload->>'contact_instagram', p_payload->>'payment_instructions',
    coalesce(nullif(p_payload->>'timezone',''), 'America/Argentina/Buenos_Aires'),
    upper(coalesce(nullif(p_payload->>'currency',''), 'ARS')),
    p_payload->>'legal_name', p_payload->>'tax_id', v_uid
  )
  returning id into v_id;

  perform private.log_audit('merchant.create', 'merchant', v_id, v_id, null, null,
    jsonb_build_object('name', v_name, 'slug', v_slug));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('merchant_id', v_id));
end $$;

create or replace function public.admin_merchant_update(p_merchant_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.merchants;
begin
  if not ((select private.is_owner())
          or private.has_merchant_permission(p_merchant_id, 'merchant.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para editar este comercio.');
  end if;

  select * into v_m from public.merchants m where m.id = p_merchant_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El comercio no existe.');
  end if;

  -- status y created_by NO se toman del payload: los cambia admin_merchant_set_status.
  update public.merchants m
     set name                 = coalesce(nullif(btrim(coalesce(p_payload->>'name','')), ''), m.name),
         description          = coalesce(p_payload->>'description', m.description),
         logo_path            = coalesce(p_payload->>'logo_path', m.logo_path),
         contact_phone        = coalesce(p_payload->>'contact_phone', m.contact_phone),
         contact_whatsapp     = coalesce(p_payload->>'contact_whatsapp', m.contact_whatsapp),
         contact_instagram    = coalesce(p_payload->>'contact_instagram', m.contact_instagram),
         payment_instructions = coalesce(p_payload->>'payment_instructions', m.payment_instructions),
         timezone             = coalesce(nullif(p_payload->>'timezone',''), m.timezone),
         currency             = coalesce(nullif(upper(p_payload->>'currency'),''), m.currency),
         legal_name           = coalesce(p_payload->>'legal_name', m.legal_name),
         tax_id               = coalesce(p_payload->>'tax_id', m.tax_id)
   where m.id = p_merchant_id;

  perform private.log_audit('merchant.update', 'merchant', p_merchant_id, p_merchant_id, null,
    jsonb_build_object('name', v_m.name), jsonb_build_object('payload', p_payload));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('merchant_id', p_merchant_id));
end $$;

create or replace function public.admin_merchant_set_status(
  p_merchant_id uuid,
  p_status public.merchant_status,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.merchants;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede cambiar el estado de un comercio.');
  end if;

  select * into v_m from public.merchants m where m.id = p_merchant_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El comercio no existe.');
  end if;

  if p_status = 'SUSPENDED' and (p_reason is null or char_length(btrim(p_reason)) < 5) then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indicá el motivo de la suspensión.');
  end if;

  update public.merchants m set status = p_status where m.id = p_merchant_id;

  perform private.log_audit('merchant.status_change', 'merchant', p_merchant_id, p_merchant_id, null,
    jsonb_build_object('status', v_m.status),
    jsonb_build_object('status', p_status, 'reason', p_reason));

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('merchant_id', p_merchant_id, 'status', p_status));
end $$;

-- ---------------------------------------------------------------------------
-- ASIGNAR / REVOCAR COMERCIANTE — EXCLUSIVO DEL OWNER
-- Es la única vía para crear un MERCHANT. Ni un comerciante ni un colaborador
-- pueden ejecutarla, y todo queda auditado (quién, a quién, cuándo, rol previo).
-- ---------------------------------------------------------------------------
create or replace function public.admin_assign_merchant(
  p_profile_id uuid,
  p_merchant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_prev     public.merchant_members;
  v_rol_prev text;
  v_id       uuid;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede asignar el rol de comerciante.');
  end if;

  if not exists (select 1 from public.merchants m where m.id = p_merchant_id) then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El comercio no existe.');
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_profile_id) then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El usuario no existe.');
  end if;

  select * into v_prev
    from public.merchant_members mm
   where mm.merchant_id = p_merchant_id and mm.profile_id = p_profile_id;

  v_rol_prev := v_prev.role::text;

  insert into public.merchant_members (merchant_id, profile_id, role, status, invited_by)
  values (p_merchant_id, p_profile_id, 'MERCHANT', 'ACTIVE', v_uid)
  on conflict (merchant_id, profile_id) do update
     set role         = 'MERCHANT',
         status       = 'ACTIVE',
         suspended_at = null,
         removed_at   = null,
         revoke_after = null
  returning id into v_id;

  perform private.log_audit('role.assign_merchant', 'merchant_member', v_id,
    p_merchant_id, null,
    jsonb_build_object('role', v_rol_prev, 'status', v_prev.status),
    jsonb_build_object('role', 'MERCHANT', 'status', 'ACTIVE'),
    jsonb_build_object('assigned_to', p_profile_id, 'assigned_by', v_uid));

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('member_id', v_id, 'role', 'MERCHANT'));
end $$;

create or replace function public.admin_revoke_merchant(
  p_profile_id uuid,
  p_merchant_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_prev public.merchant_members;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede revocar el rol de comerciante.');
  end if;

  if p_reason is null or char_length(btrim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indicá el motivo (mínimo 5 caracteres).');
  end if;

  select * into v_prev
    from public.merchant_members mm
   where mm.merchant_id = p_merchant_id and mm.profile_id = p_profile_id;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND',
      'message', 'Ese usuario no es parte del comercio.');
  end if;

  update public.merchant_members mm
     set status       = 'REMOVED',
         removed_at   = now(),
         revoke_after = now() + interval '30 days'   -- ventana de gracia (D9)
   where mm.id = v_prev.id;

  perform private.log_audit('role.revoke_merchant', 'merchant_member', v_prev.id,
    p_merchant_id, null,
    jsonb_build_object('role', v_prev.role, 'status', v_prev.status),
    jsonb_build_object('status', 'REMOVED', 'reason', btrim(p_reason)),
    jsonb_build_object('revoked_from', p_profile_id, 'revoked_by', v_uid,
                       'grace_until', now() + interval '30 days'));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('member_id', v_prev.id));
end $$;

-- ---------------------------------------------------------------------------
-- STAFF DEL COMERCIO (nunca puede otorgar MERCHANT)
-- ---------------------------------------------------------------------------
create or replace function public.staff_add(
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
  v_uid     uuid := (select auth.uid());
  v_profile uuid;
  v_id      uuid;
  v_prev    public.merchant_members;
begin
  if not ((select private.is_owner())
          or private.has_merchant_permission(p_merchant_id, 'staff.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para administrar el staff de este comercio.');
  end if;

  -- Un comerciante NO puede crear otro comerciante. Sólo el OWNER puede.
  if p_role = 'MERCHANT' and not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede asignar el rol de comerciante.');
  end if;

  select p.id into v_profile
    from public.profiles p
   where lower(p.email) = lower(btrim(coalesce(p_email,'')))
   limit 1;

  if v_profile is null then
    return jsonb_build_object('ok', false, 'code', 'USER_NOT_FOUND',
      'message', 'No hay un usuario registrado con ese email.');
  end if;

  select * into v_prev
    from public.merchant_members mm
   where mm.merchant_id = p_merchant_id and mm.profile_id = v_profile;

  if v_prev.role = 'MERCHANT' and not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No podés modificar a otro comerciante.');
  end if;

  insert into public.merchant_members (merchant_id, profile_id, role, status, invited_by)
  values (p_merchant_id, v_profile, p_role, 'ACTIVE', v_uid)
  on conflict (merchant_id, profile_id) do update
     set role = excluded.role, status = 'ACTIVE',
         suspended_at = null, removed_at = null, revoke_after = null
  returning id into v_id;

  perform private.log_audit('role.assign_collaborator', 'merchant_member', v_id,
    p_merchant_id, null,
    jsonb_build_object('role', v_prev.role, 'status', v_prev.status),
    jsonb_build_object('role', p_role, 'status', 'ACTIVE'),
    jsonb_build_object('profile_id', v_profile));

  perform private.fn_notify(v_profile, 'staff.added',
    'Te agregaron a un comercio',
    'Ya podés entrar al panel con tu cuenta.', p_merchant_id, null, null);

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('member_id', v_id, 'profile_id', v_profile, 'role', p_role));
end $$;

create or replace function public.staff_set_status(
  p_member_id uuid,
  p_status    public.member_status,
  p_reason    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.merchant_members;
begin
  select * into v_m from public.merchant_members mm where mm.id = p_member_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El miembro no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_m.merchant_id, 'staff.suspend')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para suspender staff de este comercio.');
  end if;

  -- Nadie toca a un MERCHANT salvo el OWNER.
  if v_m.role = 'MERCHANT' and not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No podés modificar a un comerciante.');
  end if;

  update public.merchant_members mm
     set status       = p_status,
         suspended_at = case when p_status = 'SUSPENDED' then now() else null end,
         removed_at   = case when p_status = 'REMOVED'   then now() else null end,
         revoke_after = case when p_status = 'REMOVED'   then now() + interval '30 days' else null end
   where mm.id = p_member_id;

  perform private.log_audit('role.suspend_collaborator', 'merchant_member', p_member_id,
    v_m.merchant_id, null,
    jsonb_build_object('status', v_m.status),
    jsonb_build_object('status', p_status, 'reason', p_reason));

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('member_id', p_member_id, 'status', p_status));
end $$;

create or replace function public.staff_set_permission(
  p_member_id       uuid,
  p_permission_code text,
  p_granted         boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m public.merchant_members;
begin
  select * into v_m from public.merchant_members mm where mm.id = p_member_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El miembro no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_m.merchant_id, 'staff.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para administrar permisos de este comercio.');
  end if;

  -- TECHO: un colaborador nunca recibe un permiso que MERCHANT no tenga.
  if p_granted and not exists (
    select 1 from public.role_permissions rp
     where rp.role_code = 'MERCHANT' and rp.permission_code = p_permission_code
  ) then
    return jsonb_build_object('ok', false, 'code', 'PERMISSION_ABOVE_CEILING',
      'message', 'Ese permiso no es delegable.');
  end if;

  insert into public.member_permissions (merchant_member_id, permission_code, granted, granted_by)
  values (p_member_id, p_permission_code, p_granted, (select auth.uid()))
  on conflict (merchant_member_id, permission_code) do update
     set granted = excluded.granted, granted_by = excluded.granted_by;

  perform private.log_audit(
    case when p_granted then 'permission.override_set' else 'permission.override_remove' end,
    'merchant_member', p_member_id, v_m.merchant_id, null, null,
    jsonb_build_object('permission', p_permission_code, 'granted', p_granted));

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('member_id', p_member_id,
                       'permission', p_permission_code, 'granted', p_granted));
end $$;

-- ---------------------------------------------------------------------------
-- CONFIGURACIÓN
-- El comerciante se RECHAZA (no se clampa en silencio): un valor distinto del
-- que escribió el usuario es un problema de confianza, no una cortesía.
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_system_setting(p_key text, p_value jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s public.system_settings;
  v_txt text := p_value #>> '{}';
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma modifica la configuración global.');
  end if;

  select * into v_s from public.system_settings ss where ss.key = p_key;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'UNKNOWN_SETTING', 'message', 'La clave no existe.');
  end if;

  if v_s.value_type in ('int','numeric') then
    if v_txt !~ '^-?[0-9]+(\.[0-9]+)?$' then
      return jsonb_build_object('ok', false, 'code', 'INVALID_VALUE', 'message', 'Se esperaba un número.');
    end if;
    if v_s.min_value is not null and v_txt::numeric < v_s.min_value then
      return jsonb_build_object('ok', false, 'code', 'OUT_OF_RANGE',
        'message', format('El mínimo permitido es %s.', v_s.min_value));
    end if;
    if v_s.max_value is not null and v_txt::numeric > v_s.max_value then
      return jsonb_build_object('ok', false, 'code', 'OUT_OF_RANGE',
        'message', format('El máximo permitido es %s.', v_s.max_value));
    end if;
  elsif v_s.value_type = 'bool' then
    if v_txt not in ('true','false') then
      return jsonb_build_object('ok', false, 'code', 'INVALID_VALUE', 'message', 'Se esperaba true o false.');
    end if;
  end if;

  update public.system_settings ss
     set value = p_value, updated_by = (select auth.uid())
   where ss.key = p_key;

  perform private.log_audit('settings.system_change', 'system_setting', null, null, null,
    jsonb_build_object('key', p_key, 'value', v_s.value),
    jsonb_build_object('key', p_key, 'value', p_value));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('key', p_key, 'value', p_value));
end $$;

create or replace function public.merchant_set_setting(p_merchant_id uuid, p_key text, p_value jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_s public.system_settings;
  v_txt text := p_value #>> '{}';
  v_new numeric;
  v_lim numeric;
begin
  if not ((select private.is_owner()) or private.is_merchant_of(p_merchant_id)) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para cambiar la configuración de este comercio.');
  end if;

  select * into v_s from public.system_settings ss where ss.key = p_key;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'UNKNOWN_SETTING', 'message', 'La clave no existe.');
  end if;

  if not (select private.is_owner()) then
    if v_s.is_owner_only or not v_s.editable_by_merchant then
      return jsonb_build_object('ok', false, 'code', 'OWNER_ONLY_SETTING',
        'message', 'Esa configuración es global y la administra la plataforma.');
    end if;
    -- TECHO GLOBAL: se rechaza, no se recorta en silencio.
    if v_s.direction <> 'none' then
      if v_txt !~ '^-?[0-9]+(\.[0-9]+)?$' then
        return jsonb_build_object('ok', false, 'code', 'INVALID_VALUE', 'message', 'Se esperaba un número.');
      end if;
      v_new := v_txt::numeric;
      v_lim := coalesce(nullif(v_s.value #>> '{}','')::numeric, v_new);
      if v_s.direction = 'ceiling' and v_new > v_lim then
        return jsonb_build_object('ok', false, 'code', 'SETTING_EXCEEDS_GLOBAL_LIMIT',
          'message', format('El máximo permitido por la plataforma es %s.', v_lim),
          'details', jsonb_build_object('global_limit', v_lim, 'requested', v_new));
      end if;
      if v_s.direction = 'floor' and v_new < v_lim then
        return jsonb_build_object('ok', false, 'code', 'SETTING_BELOW_GLOBAL_LIMIT',
          'message', format('El mínimo permitido por la plataforma es %s.', v_lim),
          'details', jsonb_build_object('global_limit', v_lim, 'requested', v_new));
      end if;
    end if;
  end if;

  insert into public.merchant_settings (merchant_id, key, value, updated_by)
  values (p_merchant_id, p_key, p_value, (select auth.uid()))
  on conflict (merchant_id, key) do update
     set value = excluded.value, updated_by = excluded.updated_by;

  perform private.log_audit('settings.merchant_change', 'merchant_setting', null,
    p_merchant_id, null, null, jsonb_build_object('key', p_key, 'value', p_value));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('key', p_key, 'value', p_value));
end $$;

-- ---------------------------------------------------------------------------
-- BLOQUEOS (antiabuso manual y automático)
-- El comerciante bloquea en SU comercio; nunca levanta un bloqueo GLOBAL.
-- ---------------------------------------------------------------------------
create or replace function public.security_block_add(
  p_subject_profile_id uuid,
  p_merchant_id uuid,
  p_event_id    uuid,
  p_reason      text,
  p_hours       int default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_id    uuid;
  v_scope text;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indicá el motivo del bloqueo (mínimo 5 caracteres).');
  end if;

  v_scope := case when p_event_id is not null then 'EVENT'
                  when p_merchant_id is not null then 'MERCHANT'
                  else 'GLOBAL' end;

  if v_scope = 'GLOBAL' then
    if not (select private.is_owner()) then
      return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
        'message', 'Sólo la plataforma puede aplicar un bloqueo global.');
    end if;
  else
    if not ((select private.is_owner())
            or private.has_merchant_permission(p_merchant_id, 'reservation.cancel')) then
      return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
        'message', 'No tenés permiso para bloquear participantes de este comercio.');
    end if;
  end if;

  if p_event_id is not null and not exists (
    select 1 from public.events e where e.id = p_event_id and e.merchant_id = p_merchant_id
  ) then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT',
      'message', 'El evento no pertenece a ese comercio.');
  end if;

  insert into public.security_blocks (
    scope, merchant_id, event_id, subject_profile_id, reason, source, blocked_by, blocked_until
  ) values (
    v_scope, p_merchant_id, p_event_id, p_subject_profile_id, btrim(p_reason), 'MANUAL', v_uid,
    case when p_hours is null then null else now() + make_interval(hours => p_hours) end
  )
  returning id into v_id;

  perform private.log_audit('security.block', 'security_block', v_id, p_merchant_id, p_event_id,
    null, jsonb_build_object('scope', v_scope, 'reason', btrim(p_reason), 'hours', p_hours),
    jsonb_build_object('blocked_profile', p_subject_profile_id));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('block_id', v_id));
end $$;

create or replace function public.security_block_lift(p_block_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_b public.security_blocks;
begin
  select * into v_b from public.security_blocks sb where sb.id = p_block_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El bloqueo no existe.');
  end if;

  if v_b.scope = 'GLOBAL' and not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo la plataforma puede levantar un bloqueo global.');
  end if;

  if v_b.scope <> 'GLOBAL'
     and not ((select private.is_owner())
              or private.has_merchant_permission(v_b.merchant_id, 'reservation.cancel')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para desbloquear en este comercio.');
  end if;

  if p_reason is null or char_length(btrim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indicá el motivo (mínimo 5 caracteres).');
  end if;

  update public.security_blocks sb
     set lifted_at = now(), lift_reason = btrim(p_reason)
   where sb.id = p_block_id and sb.lifted_at is null;

  perform private.log_audit('security.unblock', 'security_block', p_block_id,
    v_b.merchant_id, v_b.event_id, jsonb_build_object('lifted_at', null),
    jsonb_build_object('lifted_at', now(), 'reason', btrim(p_reason)));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('block_id', p_block_id));
end $$;

-- ---------------------------------------------------------------------------
-- CONVERSIÓN ANÓNIMO → REGISTRADO y notificaciones
-- ---------------------------------------------------------------------------
create or replace function public.profile_mark_converted()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_p   public.profiles;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', 'Necesitás una sesión.');
  end if;

  select * into v_p from public.profiles p where p.id = v_uid;

  if v_p.is_anonymous = false then
    return jsonb_build_object('ok', true, 'data', jsonb_build_object('already_converted', true));
  end if;

  -- El UUID NO cambia: por eso el historial del participante sobrevive entero.
  update public.profiles p
     set is_anonymous = false, converted_at = now()
   where p.id = v_uid;

  perform private.log_audit('account.converted', 'profile', v_uid, null, null,
    jsonb_build_object('is_anonymous', true),
    jsonb_build_object('is_anonymous', false));

  perform private.fn_notify(v_uid, 'account.converted', 'Tu cuenta quedó activa',
    'Ahora podés entrar desde cualquier dispositivo y ver todo tu historial.');

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('converted', true));
end $$;

create or replace function public.notifications_mark_read(p_ids uuid[])
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_n   int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', 'Necesitás una sesión.');
  end if;

  update public.notifications n
     set status = 'READ', read_at = now()
   where n.id = any(p_ids)
     and n.recipient_profile_id = v_uid
     and n.read_at is null;

  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object('updated', v_n));
end $$;

create or replace function public.admin_draw_source_upsert(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo la plataforma administra el catálogo de loterías.');
  end if;

  insert into public.draw_sources (code, name, kind, jurisdiction, shifts, timezone, is_active, sort_order)
  values (
    upper(nullif(btrim(coalesce(p_payload->>'code','')), '')),
    nullif(btrim(coalesce(p_payload->>'name','')), ''),
    coalesce(nullif(p_payload->>'kind',''), 'OTHER'),
    p_payload->>'jurisdiction',
    coalesce(
      (select array_agg(t.value) from jsonb_array_elements_text(p_payload->'shifts') as t(value)),
      array['UNICA']
    ),
    coalesce(nullif(p_payload->>'timezone',''), 'America/Argentina/Buenos_Aires'),
    coalesce(nullif(p_payload->>'is_active','')::boolean, true),
    coalesce(nullif(p_payload->>'sort_order','')::int, 0)
  )
  on conflict (code) do update
     set name         = excluded.name,
         kind         = excluded.kind,
         jurisdiction = excluded.jurisdiction,
         shifts       = excluded.shifts,
         timezone     = excluded.timezone,
         is_active    = excluded.is_active,
         sort_order   = excluded.sort_order
  returning id into v_id;

  perform private.log_audit('draw_source.upsert', 'draw_source', v_id, null, null, null,
    jsonb_build_object('code', p_payload->>'code', 'name', p_payload->>'name'));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('draw_source_id', v_id));
end $$;

-- ---------------------------------------------------------------------------
-- GRANTS
-- Ojo: las RPC de administración se otorgan a `authenticated` porque quien las
-- llama ES un usuario autenticado (el OWNER). La guarda real es el chequeo de
-- is_owner() DENTRO de la función, no el GRANT.
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
  v_sig regprocedure;
  v_rpcs text[] := array[
    'admin_merchant_create(jsonb)',
    'admin_merchant_update(uuid,jsonb)',
    'admin_merchant_set_status(uuid,public.merchant_status,text)',
    'admin_assign_merchant(uuid,uuid)',
    'admin_revoke_merchant(uuid,uuid,text)',
    'admin_set_system_setting(text,jsonb)',
    'admin_draw_source_upsert(jsonb)',
    'staff_add(uuid,text,public.member_role)',
    'staff_set_status(uuid,public.member_status,text)',
    'staff_set_permission(uuid,text,boolean)',
    'merchant_set_setting(uuid,text,jsonb)',
    'security_block_add(uuid,uuid,uuid,text,int)',
    'security_block_lift(uuid,text)',
    'profile_mark_converted()',
    'notifications_mark_read(uuid[])'
  ];
begin
  foreach f in array v_rpcs loop
    v_sig := ('public.' || f)::regprocedure;
    execute format('revoke all on function %s from public, anon', v_sig);
    execute format('grant execute on function %s to authenticated', v_sig);
  end loop;
end $$;