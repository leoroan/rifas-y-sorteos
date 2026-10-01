-- =============================================================================
-- 0012_rpc_events.sql
-- Ciclo de vida del evento, premios y aceptación de términos.
-- Ninguna RPC lee merchant_id/profile_id/status del payload: los deriva de la
-- fila real o de auth.uid().
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: extrae y valida los campos editables del payload.
-- Los campos NO listados acá se ignoran por completo.
-- ---------------------------------------------------------------------------
create or replace function private.fn_event_payload(p_payload jsonb)
returns table (
  kind text, title text, slug text, description text, cover_path text,
  starts_at timestamptz, participation_ends_at timestamptz, expected_draw_at timestamptz,
  timezone text, numbers_from int, numbers_to int, number_padding int,
  price_per_number numeric, currency text,
  max_registered int, max_anonymous int,
  ttl_registered interval, ttl_anonymous interval, review_ttl interval,
  winner_method text, winner_rule text, draw_source_id uuid, draw_shift text,
  draw_source_detail text, draw_fallback_policy text,
  legal_status text, legal_notes text, terms_version_id uuid
)
language sql
immutable
set search_path = ''
as $$
  select
    coalesce(nullif(btrim(p_payload->>'kind'), ''), 'RAFFLE'),
    nullif(btrim(coalesce(p_payload->>'title','')), ''),
    nullif(lower(btrim(coalesce(p_payload->>'slug',''))), ''),
    p_payload->>'description',
    p_payload->>'cover_path',
    coalesce(nullif(p_payload->>'starts_at','')::timestamptz, now()),
    nullif(p_payload->>'participation_ends_at','')::timestamptz,
    nullif(p_payload->>'expected_draw_at','')::timestamptz,
    coalesce(nullif(p_payload->>'timezone',''), 'America/Argentina/Buenos_Aires'),
    nullif(p_payload->>'numbers_from','')::int,
    nullif(p_payload->>'numbers_to','')::int,
    coalesce(nullif(p_payload->>'number_padding','')::int, 3),
    coalesce(nullif(p_payload->>'price_per_number','')::numeric, 0),
    upper(coalesce(nullif(p_payload->>'currency',''), 'ARS')),
    coalesce(nullif(p_payload->>'max_numbers_registered','')::int, 10),
    coalesce(nullif(p_payload->>'max_numbers_anonymous','')::int, 3),
    coalesce(nullif(p_payload->>'reservation_ttl_registered','')::interval, interval '24 hours'),
    coalesce(nullif(p_payload->>'reservation_ttl_anonymous','')::interval, interval '2 hours'),
    coalesce(nullif(p_payload->>'review_ttl','')::interval, interval '72 hours'),
    coalesce(nullif(p_payload->>'winner_method',''), 'RANDOM_SEEDED'),
    nullif(p_payload->>'winner_rule',''),
    nullif(p_payload->>'draw_source_id','')::uuid,
    nullif(p_payload->>'draw_shift',''),
    nullif(p_payload->>'draw_source_detail',''),
    coalesce(nullif(p_payload->>'draw_fallback_policy',''), 'HOLD_FOR_REVIEW'),
    coalesce(nullif(p_payload->>'legal_status',''), 'PENDING_REVIEW'),
    nullif(p_payload->>'legal_notes',''),
    nullif(p_payload->>'terms_version_id','')::uuid;
$$;

-- ---------------------------------------------------------------------------
-- CREAR EVENTO
-- ---------------------------------------------------------------------------
create or replace function public.event_create(p_merchant_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v     record;
  v_id  uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', 'Necesitás una sesión.');
  end if;

  if not private.has_merchant_permission(p_merchant_id, 'event.create') then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para crear eventos en este comercio.');
  end if;

  select * into v from private.fn_event_payload(p_payload);

  if v.title is null or char_length(v.title) < 3 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_TITLE', 'message', 'Falta el título.');
  end if;
  if v.slug is null then
    return jsonb_build_object('ok', false, 'code', 'INVALID_SLUG',
      'message', 'Falta el identificador del evento (sólo minúsculas, números y guiones).');
  end if;
  if v.participation_ends_at is null then
    return jsonb_build_object('ok', false, 'code', 'INVALID_DATES', 'message', 'Falta la fecha de cierre.');
  end if;
  if v.numbers_from is null or v.numbers_to is null then
    return jsonb_build_object('ok', false, 'code', 'INVALID_NUMBERS', 'message', 'Falta el rango de números.');
  end if;

  if exists (
    select 1 from public.events e
     where e.merchant_id = p_merchant_id and lower(e.slug) = v.slug
  ) then
    return jsonb_build_object('ok', false, 'code', 'SLUG_TAKEN',
      'message', 'Ya existe un evento con ese identificador.');
  end if;

  insert into public.events (
    merchant_id, kind, title, slug, description, cover_path, status,
    starts_at, participation_ends_at, expected_draw_at, timezone,
    numbers_from, numbers_to, number_padding,
    price_per_number, currency,
    max_numbers_registered, max_numbers_anonymous,
    reservation_ttl_registered, reservation_ttl_anonymous, review_ttl,
    winner_method, winner_rule, draw_source_id, draw_shift, draw_source_detail,
    draw_fallback_policy, legal_status, legal_notes, terms_version_id, created_by
  ) values (
    p_merchant_id, v.kind::public.event_kind, v.title, v.slug, v.description, v.cover_path, 'DRAFT',
    v.starts_at, v.participation_ends_at, v.expected_draw_at, v.timezone,
    v.numbers_from, v.numbers_to, v.number_padding,
    v.price_per_number, v.currency,
    v.max_registered, v.max_anonymous,
    v.ttl_registered, v.ttl_anonymous, v.review_ttl,
    v.winner_method, v.winner_rule, v.draw_source_id, v.draw_shift, v.draw_source_detail,
    v.draw_fallback_policy, v.legal_status, v.legal_notes, v.terms_version_id, v_uid
  )
  returning id into v_id;

  perform private.log_audit('event.create', 'event', v_id, p_merchant_id, v_id, null,
    jsonb_build_object('title', v.title, 'status', 'DRAFT',
                       'numbers', jsonb_build_array(v.numbers_from, v.numbers_to)));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('event_id', v_id, 'status', 'DRAFT'));
end $$;

-- ---------------------------------------------------------------------------
-- ACTUALIZAR EVENTO
-- Los triggers de la tabla hacen cumplir la inmutabilidad (números y términos);
-- acá se valida el permiso y se arma la lista de campos editables.
-- ---------------------------------------------------------------------------
create or replace function public.event_update(p_event_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_e   public.events;
  v     record;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.update')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para modificar este evento.');
  end if;

  select * into v from private.fn_event_payload(p_payload);

  update public.events e
     set kind                       = coalesce(v.kind::public.event_kind, e.kind),
         title                      = coalesce(v.title, e.title),
         description                = coalesce(v.description, e.description),
         cover_path                 = coalesce(v.cover_path, e.cover_path),
         starts_at                  = coalesce(v.starts_at, e.starts_at),
         participation_ends_at      = coalesce(v.participation_ends_at, e.participation_ends_at),
         expected_draw_at           = coalesce(v.expected_draw_at, e.expected_draw_at),
         timezone                   = coalesce(v.timezone, e.timezone),
         numbers_from               = coalesce(v.numbers_from, e.numbers_from),
         numbers_to                 = coalesce(v.numbers_to, e.numbers_to),
         number_padding             = coalesce(v.number_padding, e.number_padding),
         price_per_number           = coalesce(v.price_per_number, e.price_per_number),
         currency                   = coalesce(v.currency, e.currency),
         max_numbers_registered     = coalesce(v.max_registered, e.max_numbers_registered),
         max_numbers_anonymous      = coalesce(v.max_anonymous, e.max_numbers_anonymous),
         reservation_ttl_registered = coalesce(v.ttl_registered, e.reservation_ttl_registered),
         reservation_ttl_anonymous  = coalesce(v.ttl_anonymous, e.reservation_ttl_anonymous),
         review_ttl                 = coalesce(v.review_ttl, e.review_ttl),
         winner_method              = coalesce(v.winner_method, e.winner_method),
         winner_rule                = coalesce(v.winner_rule, e.winner_rule),
         draw_source_id             = coalesce(v.draw_source_id, e.draw_source_id),
         draw_shift                 = coalesce(v.draw_shift, e.draw_shift),
         draw_source_detail         = coalesce(v.draw_source_detail, e.draw_source_detail),
         draw_fallback_policy       = coalesce(v.draw_fallback_policy, e.draw_fallback_policy),
         legal_status               = coalesce(v.legal_status, e.legal_status),
         legal_notes                = coalesce(v.legal_notes, e.legal_notes),
         terms_version_id           = coalesce(v.terms_version_id, e.terms_version_id),
         updated_by                 = v_uid
   where e.id = p_event_id;

  perform private.log_audit('event.update', 'event', p_event_id, v_e.merchant_id, p_event_id,
    jsonb_build_object('title', v_e.title, 'status', v_e.status,
                       'numbers_from', v_e.numbers_from, 'numbers_to', v_e.numbers_to),
    jsonb_build_object('title', coalesce(v.title, v_e.title),
                       'numbers_from', coalesce(v.numbers_from, v_e.numbers_from),
                       'numbers_to', coalesce(v.numbers_to, v_e.numbers_to)));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('event_id', p_event_id));
end $$;

-- ---------------------------------------------------------------------------
-- PUBLICAR EVENTO
-- Materializa los números y congela el rango en la MISMA transacción. Falla
-- entera si falta algo: no existe un evento publicado a medias.
-- ---------------------------------------------------------------------------
create or replace function public.event_publish(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_e       public.events;
  v_terms   uuid;
  v_creados int;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.publish')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para publicar este evento.');
  end if;

  if v_e.status <> 'DRAFT' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Sólo se puede publicar un evento en borrador.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  if not exists (
    select 1 from public.prizes p where p.event_id = p_event_id and p.status = 'ACTIVE'
  ) then
    return jsonb_build_object('ok', false, 'code', 'NO_PRIZES',
      'message', 'Cargá al menos un premio antes de publicar.');
  end if;

  if v_e.winner_method = 'EXTERNAL_LOTTERY' and v_e.draw_source_id is null then
    return jsonb_build_object('ok', false, 'code', 'DRAW_SOURCE_REQUIRED',
      'message', 'Elegí la lotería de referencia o cambiá el método de sorteo.');
  end if;

  v_terms := v_e.terms_version_id;
  if v_terms is null then
    select tv.id into v_terms
      from public.terms_versions tv
     where tv.scope = 'GLOBAL' and tv.kind = 'TERMS' and tv.is_current
     limit 1;
    if v_terms is null then
      return jsonb_build_object('ok', false, 'code', 'TERMS_NOT_CONFIGURED',
        'message', 'No hay condiciones vigentes cargadas. Avisá al administrador.');
    end if;
  end if;

  v_creados := private.fn_materialize_event_numbers(
                 p_event_id, v_e.numbers_from, v_e.numbers_to, v_e.number_padding);

  update public.events e
     set status            = 'PUBLISHED',
         published_at      = coalesce(e.published_at, now()),
         numbers_locked_at = coalesce(e.numbers_locked_at, now()),  -- a partir de acá, inmutable
         terms_version_id  = v_terms,
         updated_by        = v_uid
   where e.id = p_event_id;

  perform private.log_audit('event.publish', 'event', p_event_id, v_e.merchant_id, p_event_id,
    jsonb_build_object('status', 'DRAFT'),
    jsonb_build_object('status', 'PUBLISHED', 'numbers_created', v_creados,
                       'from', v_e.numbers_from, 'to', v_e.numbers_to),
    jsonb_build_object('legal_status', v_e.legal_status));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'event_id', p_event_id,
    'status', 'PUBLISHED',
    'numbers_created', v_creados,
    'numbers_from', v_e.numbers_from,
    'numbers_to', v_e.numbers_to,
    'legal_status', v_e.legal_status));
end $$;

-- ---------------------------------------------------------------------------
-- CERRAR EVENTO
-- No se aceptan más reservas. Los holds VÁLIDOS no se fuerzan: se les respeta
-- su plazo (si no, el participante que hizo todo bien perdería los números
-- porque al comerciante se le ocurrió cerrar antes). Sólo se expiran los que ya
-- vencieron, y se informa cuántos quedan vivos.
-- ---------------------------------------------------------------------------
create or replace function public.event_close(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_e     public.events;
  v_pend  int;
  v_sub   int;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.close')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para cerrar este evento.');
  end if;

  if v_e.status not in ('PUBLISHED','OPEN') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'El evento no está abierto.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  perform public.reservations_expire_stale(500);

  update public.events e
     set status = 'CLOSED', closed_at = now(), updated_by = v_uid
   where e.id = p_event_id;

  select count(*) into v_pend
    from public.reservations r
   where r.event_id = p_event_id and r.status = 'PENDING';

  select count(*) into v_sub
    from public.reservations r
   where r.event_id = p_event_id and r.status = 'PAYMENT_SUBMITTED';

  perform private.log_audit('event.status_change', 'event', p_event_id, v_e.merchant_id, p_event_id,
    jsonb_build_object('status', v_e.status),
    jsonb_build_object('status', 'CLOSED', 'pending', v_pend, 'submitted', v_sub));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'event_id', p_event_id, 'status', 'CLOSED',
    'pending_reservations', v_pend,
    'submitted_receipts', v_sub));
end $$;

-- ---------------------------------------------------------------------------
-- CANCELAR EVENTO
-- Los números PAGADOS no se tocan: hay dinero de por medio y eso se resuelve
-- a mano. Los holds vivos se cancelan y sus números quedan marcados CANCELLED.
-- ---------------------------------------------------------------------------
create or replace function public.event_cancel(p_event_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_e       public.events;
  v_res_ids uuid[];
  v_paid    int;
  v_id      uuid;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.cancel')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para cancelar este evento.');
  end if;

  if v_e.status in ('DRAWN','CANCELLED') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Un evento sorteado o ya cancelado no se puede cancelar.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  if p_reason is null or char_length(btrim(p_reason)) < 5 then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indicá el motivo de la cancelación (mínimo 5 caracteres).');
  end if;

  select coalesce(array_agg(r.id), '{}')
    into v_res_ids
    from public.reservations r
   where r.event_id = p_event_id
     and r.status in ('PENDING','PAYMENT_SUBMITTED');

  update public.reservation_numbers rn
     set released_at = now(), release_reason = 'CANCELLED'
   where rn.reservation_id = any(v_res_ids)
     and rn.released_at is null;

  -- Los números mantienen su reservation_id: el CHECK exige que todo estado
  -- distinto de AVAILABLE tenga tenedor, y queremos conservar el rastro.
  update public.event_numbers en
     set status = 'CANCELLED', updated_at = now()
   where en.reservation_id = any(v_res_ids);

  update public.reservations r
     set status = 'CANCELLED',
         closed_at = now(),
         cancel_reason = btrim(p_reason)
   where r.id = any(v_res_ids);

  select count(*) into v_paid
    from public.event_numbers en
   where en.event_id = p_event_id and en.status in ('PAID','WINNER');

  update public.events e
     set status = 'CANCELLED',
         cancelled_at = now(),
         cancellation_reason = btrim(p_reason),
         updated_by = v_uid
   where e.id = p_event_id;

  perform private.log_audit('event.cancel', 'event', p_event_id, v_e.merchant_id, p_event_id,
    jsonb_build_object('status', v_e.status),
    jsonb_build_object('status', 'CANCELLED', 'reason', btrim(p_reason),
                       'reservations_cancelled', coalesce(array_length(v_res_ids, 1), 0),
                       'paid_numbers_untouched', v_paid));

  foreach v_id in array v_res_ids loop
    perform private.fn_notify(
      (select profile_id from public.reservations where id = v_id),
      'event.cancelled', 'El sorteo fue cancelado',
      format('%s — Si ya habías pagado, contactá al comercio.', btrim(p_reason)),
      v_e.merchant_id, p_event_id, v_id);
  end loop;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'event_id', p_event_id, 'status', 'CANCELLED',
    'reservations_cancelled', coalesce(array_length(v_res_ids, 1), 0),
    'paid_numbers_untouched', v_paid));
end $$;

-- ---------------------------------------------------------------------------
-- PREMIOS
-- ---------------------------------------------------------------------------
create or replace function public.prize_upsert(
  p_event_id uuid,
  p_prize_id uuid,
  p_payload  jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e     public.events;
  v_id    uuid := coalesce(p_prize_id, gen_random_uuid());
  v_title text := nullif(btrim(coalesce(p_payload->>'title','')), '');
  v_pos   int  := coalesce(nullif(p_payload->>'position','')::int, 1);
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'prize.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para administrar premios de este comercio.');
  end if;

  if v_e.status <> 'DRAFT' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Los premios se editan sólo mientras el evento está en borrador.');
  end if;

  if v_title is null or char_length(v_title) < 2 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_TITLE', 'message', 'Falta el nombre del premio.');
  end if;

  insert into public.prizes (
    id, event_id, position, title, description, image_path,
    estimated_value, currency, conditions, status, created_by
  ) values (
    v_id, p_event_id, v_pos, v_title,
    p_payload->>'description', p_payload->>'image_path',
    nullif(p_payload->>'estimated_value','')::numeric,
    nullif(p_payload->>'currency',''),
    p_payload->>'conditions',
    coalesce(nullif(p_payload->>'status',''), 'ACTIVE'),
    (select auth.uid())
  )
  on conflict (id) do update
     set position        = excluded.position,
         title           = excluded.title,
         description     = excluded.description,
         image_path      = excluded.image_path,
         estimated_value = excluded.estimated_value,
         currency        = excluded.currency,
         conditions      = excluded.conditions,
         status          = excluded.status;

  perform private.log_audit(
    case when p_prize_id is null then 'prize.create' else 'prize.update' end,
    'prize', v_id, v_e.merchant_id, p_event_id, null,
    jsonb_build_object('title', v_title, 'position', v_pos));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('prize_id', v_id));
end $$;

create or replace function public.prize_delete(p_prize_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.prizes;
  v_e public.events;
begin
  select * into v_p from public.prizes p where p.id = p_prize_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El premio no existe.');
  end if;

  select * into v_e from public.events e where e.id = v_p.event_id;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'prize.manage')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para administrar premios de este comercio.');
  end if;

  if v_e.status <> 'DRAFT' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Los premios se editan sólo mientras el evento está en borrador.');
  end if;

  delete from public.prizes p where p.id = p_prize_id;

  perform private.log_audit('prize.delete', 'prize', p_prize_id, v_e.merchant_id, v_e.id,
    jsonb_build_object('title', v_p.title, 'position', v_p.position), null);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('prize_id', p_prize_id));
end $$;

-- ---------------------------------------------------------------------------
-- ACEPTAR TÉRMINOS
-- Escribe la evidencia (append-only). El hash lo copia de la versión real: no
-- se puede "aceptar" un texto inventado. Idempotente.
-- ---------------------------------------------------------------------------
create or replace function public.terms_accept(
  p_terms_version_id uuid,
  p_event_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_hash text;
  v_id   uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', 'Necesitás una sesión.');
  end if;

  select tv.content_hash into v_hash
    from public.terms_versions tv
   where tv.id = p_terms_version_id;

  if v_hash is null then
    return jsonb_build_object('ok', false, 'code', 'UNKNOWN_TERMS_VERSION',
      'message', 'La versión de las condiciones no existe.');
  end if;

  select ta.id into v_id
    from public.terms_acceptances ta
   where ta.profile_id = v_uid
     and ta.terms_version_id = p_terms_version_id
   limit 1;

  if v_id is not null then
    return jsonb_build_object('ok', true, 'data',
      jsonb_build_object('acceptance_id', v_id, 'already_accepted', true));
  end if;

  insert into public.terms_acceptances (
    profile_id, terms_version_id, event_id, user_type,
    content_hash_snapshot, source
  ) values (
    v_uid, p_terms_version_id, p_event_id,
    case when private.is_anonymous_user() then 'ANONYMOUS'::public.acceptance_user_type
         else 'REGISTERED'::public.acceptance_user_type end,
    v_hash, 'WEB'
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'data',
    jsonb_build_object('acceptance_id', v_id, 'already_accepted', false));
end $$;

-- ---------------------------------------------------------------------------
-- GRANTS
-- ---------------------------------------------------------------------------
revoke all on function public.event_create(uuid, jsonb)      from public, anon;
revoke all on function public.event_update(uuid, jsonb)      from public, anon;
revoke all on function public.event_publish(uuid)            from public, anon;
revoke all on function public.event_close(uuid)              from public, anon;
revoke all on function public.event_cancel(uuid, text)       from public, anon;
revoke all on function public.prize_upsert(uuid, uuid, jsonb) from public, anon;
revoke all on function public.prize_delete(uuid)             from public, anon;
revoke all on function public.terms_accept(uuid, uuid)       from public;

grant execute on function public.event_create(uuid, jsonb)       to authenticated;
grant execute on function public.event_update(uuid, jsonb)       to authenticated;
grant execute on function public.event_publish(uuid)             to authenticated;
grant execute on function public.event_close(uuid)               to authenticated;
grant execute on function public.event_cancel(uuid, text)        to authenticated;
grant execute on function public.prize_upsert(uuid, uuid, jsonb) to authenticated;
grant execute on function public.prize_delete(uuid)              to authenticated;
-- terms_accept requiere sesión (incluso anónima de Auth): la evidencia se ata
-- a un profile_id real.
grant execute on function public.terms_accept(uuid, uuid)        to authenticated;