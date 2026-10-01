-- =============================================================================
-- 0008_helpers.sql
-- Funciones de autorización. Viven en el esquema "private", que NO está expuesto
-- a PostgREST: no son invocables desde la API aunque se conozca su nombre.
-- Todas: security definer + search_path = '' + nombres calificados.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Identidad
-- ---------------------------------------------------------------------------
create or replace function private.current_profile_id()
returns uuid
language sql stable set search_path = ''
as $$ select (select auth.uid()); $$;
comment on function private.current_profile_id() is 'Envuelve (select auth.uid()).';

create or replace function private.is_authenticated()
returns boolean
language sql stable set search_path = ''
as $$ select (select auth.uid()) is not null; $$;

-- OJO: usar SÓLO para endurecer límites, nunca para autorizar.
-- El claim puede quedar obsoleto hasta el refresh del token (ver §9.2).
create or replace function private.is_anonymous_user()
returns boolean
language sql stable set search_path = ''
as $$ select coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false); $$;
comment on function private.is_anonymous_user() is
  'Lee el claim is_anonymous. SOLO para limites mas estrictos: nunca para conceder o negar acceso.';

-- ---------------------------------------------------------------------------
-- Owner: lee la FILA REAL, no un claim. Si el OWNER es degradado, el efecto
-- es inmediato en la siguiente request.
-- ---------------------------------------------------------------------------
create or replace function private.is_owner(p_profile_id uuid default null)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
     where p.id = coalesce(p_profile_id, (select auth.uid()))
       and p.platform_role = 'OWNER'
       and p.status = 'ACTIVE'
  );
$$;

-- ---------------------------------------------------------------------------
-- Pertenencia al comercio
-- ---------------------------------------------------------------------------
create or replace function private.member_role_of(p_profile_id uuid, p_merchant_id uuid)
returns public.member_role
language sql stable security definer set search_path = ''
as $$
  select mm.role
    from public.merchant_members mm
   where mm.profile_id = p_profile_id
     and mm.merchant_id = p_merchant_id
     and mm.status = 'ACTIVE'
   limit 1;
$$;

create or replace function private.is_merchant_of(p_merchant_id uuid, p_profile_id uuid default null)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.member_role_of(coalesce(p_profile_id, (select auth.uid())), p_merchant_id) is not null;
$$;

create or replace function private.my_merchant_ids()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select mm.merchant_id
    from public.merchant_members mm
   where mm.profile_id = (select auth.uid())
     and mm.status = 'ACTIVE'
  union
  select m.id from public.merchants m where private.is_owner();
$$;

-- ---------------------------------------------------------------------------
-- Permisos efectivos: ÚNICO lugar donde se resuelve el RBAC.
-- Ninguna policy reimplementa esta lógica.
-- ---------------------------------------------------------------------------
create or replace function private.fn_effective_permissions(p_profile_id uuid, p_merchant_id uuid)
returns setof text
language sql stable security definer set search_path = ''
as $$
  with m as (
    select mm.id, mm.role
      from public.merchant_members mm
     where mm.profile_id = p_profile_id
       and mm.merchant_id = p_merchant_id
       and mm.status = 'ACTIVE'
     limit 1
  ),
  base as (
    select rp.permission_code
      from m
      join public.role_permissions rp on rp.role_code = m.role::text
  ),
  merchant_ceiling as (
    select rp.permission_code
      from public.role_permissions rp
     where rp.role_code = 'MERCHANT'
  ),
  overrides as (
    select mp.permission_code, bool_or(mp.granted) as granted
      from m
      join public.member_permissions mp on mp.merchant_member_id = m.id
     group by mp.permission_code
  )
  select b.permission_code
    from base b
   where not exists (
     select 1 from overrides o
      where o.permission_code = b.permission_code and o.granted = false
   )
  union
  select o.permission_code
    from overrides o
   where o.granted = true
     and exists (
       select 1 from merchant_ceiling mc where mc.permission_code = o.permission_code
     );
$$;
comment on function private.fn_effective_permissions(uuid, uuid) is
  'Permisos efectivos: rol - revocados + concedidos, pero un colaborador nunca recibe un permiso que MERCHANT no tenga.';

create or replace function private.has_merchant_permission(p_merchant_id uuid, p_permission text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then false
    -- El OWNER puede todo lo del comercio, EXCEPTO auto-habilitarse como
    -- participante: participar en un evento no es un privilegio de staff.
    when private.is_owner() then p_permission not in ('reservation.create','payment.receipt.upload')
    else exists (
      select 1
        from private.fn_effective_permissions((select auth.uid()), p_merchant_id) as fp(perm)
       where fp.perm = p_permission
    )
  end;
$$;

-- ---------------------------------------------------------------------------
-- Eventos
-- ---------------------------------------------------------------------------
create or replace function private.is_event_staff(p_event_id uuid, p_profile_id uuid default null)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when private.is_owner(coalesce(p_profile_id, (select auth.uid()))) then true
    else exists (
      select 1
        from public.events e
       where e.id = p_event_id
         and private.is_merchant_of(e.merchant_id, coalesce(p_profile_id, (select auth.uid())))
    )
  end;
$$;

-- REGLA DURA: el personal de un comercio no participa en sus propios eventos,
-- pero SÍ puede participar en los de otro comercio.
create or replace function private.is_merchant_staff_of_event(p_event_id uuid, p_profile_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select
    exists (
      select 1
        from public.events e
        join public.merchant_members mm on mm.merchant_id = e.merchant_id
       where e.id = p_event_id
         and mm.profile_id = p_profile_id
         and (
           mm.status in ('ACTIVE','SUSPENDED')          -- SUSPENDED sigue "relacionado"
           or (mm.status = 'REMOVED'                     -- ventana de gracia
               and mm.revoke_after is not null
               and mm.revoke_after > now())
         )
    )
    or exists (
      select 1
        from public.events e
        join public.merchants m on m.id = e.merchant_id
       where e.id = p_event_id
         and m.created_by = p_profile_id
    );
$$;
comment on function private.is_merchant_staff_of_event(uuid, uuid) is
  'Prohibicion de participar en el propio comercio. SUSPENDED y REMOVED-dentro-de-la-ventana siguen bloqueados.';

create or replace function private.can_view_event(p_event_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
      from public.events e
      join public.merchants m on m.id = e.merchant_id
     where e.id = p_event_id
       and (
         (e.status in ('PUBLISHED','OPEN','CLOSED','DRAWN') and m.status = 'ACTIVE')
         or private.is_event_staff(e.id)
       )
  );
$$;

-- Autoridad temporal: el estado describe, pero MANDA el reloj del servidor.
create or replace function private.event_is_open_now(p_event_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
      from public.events e
      join public.merchants m on m.id = e.merchant_id
     where e.id = p_event_id
       and m.status = 'ACTIVE'
       and e.status in ('PUBLISHED','OPEN')
       and now() >= e.starts_at
       and now() <= e.participation_ends_at
  );
$$;

-- ---------------------------------------------------------------------------
-- Configuración efectiva y límites
-- ---------------------------------------------------------------------------
create or replace function private.fn_effective_limits(p_event_id uuid, p_is_anonymous boolean)
returns table (max_numbers int, ttl interval, review_ttl interval)
language sql stable security definer set search_path = ''
as $$
  select
    least(
      case when p_is_anonymous then e.max_numbers_anonymous else e.max_numbers_registered end,
      coalesce(nullif(private.fn_effective_setting(e.merchant_id, 'limits.max_numbers_per_reservation') #>> '{}', '')::int, 1000)
    ) as max_numbers,
    least(
      case when p_is_anonymous then e.reservation_ttl_anonymous else e.reservation_ttl_registered end,
      coalesce(nullif(private.fn_effective_setting(e.merchant_id, 'limits.max_reservation_ttl') #>> '{}', '')::interval, interval '30 days')
    ) as ttl,
    least(
      e.review_ttl,
      coalesce(nullif(private.fn_effective_setting(e.merchant_id, 'limits.max_review_ttl') #>> '{}', '')::interval, interval '30 days')
    ) as review_ttl
  from public.events e
  where e.id = p_event_id;
$$;
comment on function private.fn_effective_limits(uuid, boolean) is
  'Limites efectivos: lo que declaro el evento, acotado por el techo global del comercio.';

-- ---------------------------------------------------------------------------
-- Bloqueos. subject_key existe como seam para IP/fingerprint a futuro: en el
-- MVP devuelve NULL porque NO se captura IP (dato personal, §10.4).
-- ---------------------------------------------------------------------------
create or replace function private.current_subject_key()
returns text
language sql stable set search_path = ''
as $$ select null::text; $$;
comment on function private.current_subject_key() is
  'Seam de antiabuso por red. MVP: NULL (no se captura IP). Si se activa, SOLO hmac(ip, salt) con retencion <= 30 dias.';

create or replace function private.is_blocked(
  p_profile_id uuid,
  p_merchant_id uuid default null,
  p_event_id uuid default null
)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
      from public.security_blocks sb
     where sb.lifted_at is null
       and sb.starts_at <= now()
       and (sb.blocked_until is null or sb.blocked_until > now())
       and (
         sb.subject_profile_id = p_profile_id
         or (sb.subject_key is not null and sb.subject_key = private.current_subject_key())
       )
       and (
         sb.scope = 'GLOBAL'
         or (sb.scope = 'MERCHANT' and p_merchant_id is not null and sb.merchant_id = p_merchant_id)
         or (sb.scope = 'EVENT'    and p_event_id    is not null and sb.event_id    = p_event_id)
       )
  );
$$;

-- ---------------------------------------------------------------------------
-- abuse_control: UNA función decide. Hoy mira contadores derivados de
-- reservations + security_blocks. Mañana suma CAPTCHA/reputación sin cambiar
-- a los llamadores.
-- ---------------------------------------------------------------------------
create or replace function private.abuse_evaluate(
  p_profile_id uuid,
  p_event_id uuid,
  p_merchant_id uuid,
  p_is_anonymous boolean
)
returns table (allowed boolean, code text, detail jsonb)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_open_event      int;
  v_open_global     int;
  v_recent          int;
  v_failed          int;
  v_max_open_event  int;
  v_max_open_global int;
  v_max_window      int;
  v_window_minutes  int;
  v_max_failed      int;
  v_failed_hours    int;
begin
  v_max_open_event  := coalesce(nullif(private.fn_effective_setting(p_merchant_id,'abuse.max_open_reservations_per_event') #>> '{}','')::int, 20);
  v_max_open_global := coalesce(nullif(private.fn_effective_setting(p_merchant_id,'abuse.max_open_reservations')          #>> '{}','')::int, 50);
  v_max_window      := coalesce(nullif(private.fn_effective_setting(p_merchant_id,'abuse.max_reservations_per_window')    #>> '{}','')::int, 10);
  v_window_minutes  := coalesce(nullif(private.fn_effective_setting(p_merchant_id,'abuse.rate_window_minutes')            #>> '{}','')::int, 60);
  v_max_failed      := coalesce(nullif(private.fn_effective_setting(p_merchant_id,'abuse.max_expired_reservations')        #>> '{}','')::int, 5);
  v_failed_hours    := coalesce(nullif(private.fn_effective_setting(p_merchant_id,'abuse.failed_window_hours')            #>> '{}','')::int, 24);

  -- Los anónimos son más estrictos (endurece, nunca afloja).
  if p_is_anonymous then
    v_max_window      := greatest(1, v_max_window / 2);
    v_max_open_global := greatest(1, v_max_open_global / 2);
  end if;

  select count(*) into v_open_event
    from public.reservations r
   where r.profile_id = p_profile_id and r.event_id = p_event_id
     and r.status in ('PENDING','PAYMENT_SUBMITTED');

  select count(*) into v_open_global
    from public.reservations r
   where r.profile_id = p_profile_id
     and r.status in ('PENDING','PAYMENT_SUBMITTED');

  select count(*) into v_recent
    from public.reservations r
   where r.profile_id = p_profile_id
     and r.created_at > now() - make_interval(mins => v_window_minutes);

  select count(*) into v_failed
    from public.reservations r
   where r.profile_id = p_profile_id
     and r.status in ('EXPIRED','REJECTED')
     and r.closed_at > now() - make_interval(hours => v_failed_hours);

  if v_failed >= v_max_failed then
    return query select false, 'COOLDOWN_ACTIVE'::text,
      jsonb_build_object('failed', v_failed, 'max', v_max_failed, 'window_hours', v_failed_hours);
    return;
  end if;

  if v_recent >= v_max_window then
    return query select false, 'RATE_LIMITED'::text,
      jsonb_build_object('recent', v_recent, 'max', v_max_window, 'window_minutes', v_window_minutes);
    return;
  end if;

  if v_open_event >= v_max_open_event then
    return query select false, 'TOO_MANY_OPEN_EVENT'::text,
      jsonb_build_object('open', v_open_event, 'max', v_max_open_event);
    return;
  end if;

  if v_open_global >= v_max_open_global then
    return query select false, 'TOO_MANY_OPEN'::text,
      jsonb_build_object('open', v_open_global, 'max', v_max_open_global);
    return;
  end if;

  return query select true, null::text, null::jsonb;
end $$;
comment on function private.abuse_evaluate(uuid, uuid, uuid, boolean) is
  'Decision unica de antiabuso. Extensible a IP/CAPTCHA/fingerprint/reputacion sin tocar a los llamadores.';

-- ---------------------------------------------------------------------------
-- Auditoría: se llama DENTRO de la misma transacción de la operación.
-- Si la operación falla, el log también: nunca hay auditoría de algo que no pasó.
-- ---------------------------------------------------------------------------
create or replace function private.log_audit(
  p_action      text,
  p_entity_type text,
  p_entity_id   uuid default null,
  p_merchant_id uuid default null,
  p_event_id    uuid default null,
  p_before      jsonb default null,
  p_after       jsonb default null,
  p_metadata    jsonb default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.audit_logs (
    id, actor_profile_id, actor_platform_role, actor_member_role,
    merchant_id, event_id, entity_type, entity_id, action, before, after, metadata
  ) values (
    v_id,
    (select auth.uid()),
    (select p.platform_role from public.profiles p where p.id = (select auth.uid())),
    (select private.member_role_of((select auth.uid()), p_merchant_id)),
    p_merchant_id, p_event_id, p_entity_type, p_entity_id, p_action,
    p_before, p_after, p_metadata
  );
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Notificaciones internas (MVP). El proveedor externo llega después.
-- ---------------------------------------------------------------------------
create or replace function private.fn_notify(
  p_recipient      uuid,
  p_type           text,
  p_title          text,
  p_body           text default null,
  p_merchant_id    uuid default null,
  p_event_id       uuid default null,
  p_reservation_id uuid default null,
  p_data           jsonb default null,
  p_channel        public.notification_channel default 'INTERNAL'
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (
    recipient_profile_id, type, channel, title, body,
    merchant_id, event_id, reservation_id, data, status, sent_at
  ) values (
    p_recipient, p_type, p_channel, p_title, p_body,
    p_merchant_id, p_event_id, p_reservation_id, p_data,
    'SENT', now()   -- INTERNAL: se entrega en el acto
  )
  on conflict do nothing
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Fórmula del sorteo aleatorio propio, reproducible y verificable.
--   seed (32 bytes del SERVIDOR) + event_id  ->  sha256  ->  60 bits  ->  módulo
-- 15 dígitos hex = 60 bits: siempre entran en un bigint con signo, así que el
-- resultado es determinista en cualquier PostgreSQL (evita la ambigüedad de
-- signo de bit(32)::int).
-- ---------------------------------------------------------------------------
create or replace function private.fn_seeded_number(
  p_seed     bytea,
  p_event_id uuid,
  p_from     int,
  p_to       int
)
returns table (computed int, digest_hex text, algorithm text)
language plpgsql stable set search_path = ''
as $$
declare
  v_h     text;
  v_total int;
  v_u     bigint;
begin
  v_total := p_to - p_from + 1;
  if v_total < 1 then
    raise exception 'INVALID_NUMBER_RANGE' using errcode = '22023';
  end if;
  if p_seed is null or octet_length(p_seed) < 16 then
    raise exception 'INVALID_SEED' using errcode = '22023';
  end if;

  v_h := encode(extensions.digest(p_seed::text || ':' || p_event_id::text, 'sha256'), 'hex');
  v_u := ('x' || substr(v_h, 1, 15))::bit(60)::bigint;

  return query select p_from + (v_u % v_total)::int, v_h, 'SHA256_MOD60_V1'::text;
end $$;
comment on function private.fn_seeded_number(bytea, uuid, int, int) is
  'Derivacion verificable del sorteo aleatorio. El seed lo genera el servidor y se publica con el resultado.';

-- ---------------------------------------------------------------------------
-- GRANTS del esquema private
-- El esquema NO está expuesto a PostgREST, así que sus funciones no son
-- alcanzables desde la API. Igual se otorga EXECUTE porque las policies y los
-- triggers se ejecutan con el rol del llamador.
-- ---------------------------------------------------------------------------
grant usage on schema private to anon, authenticated, service_role;
revoke all on schema private from public;

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private'
  loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('grant execute on function %s to anon, authenticated, service_role', f.sig);
  end loop;
end $$;