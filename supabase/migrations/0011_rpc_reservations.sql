-- =============================================================================
-- 0011_rpc_reservations.sql
-- El corazón del sistema: reservar, cancelar, expirar, subir y revisar pagos.
-- Todas las funciones devuelven jsonb con forma estable:
--   { ok: true,  data: {...} }
--   { ok: false, code: '...', message: '...', details: {...} }
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RESERVAR NÚMEROS
-- Concurrencia: UNA sola sentencia hace el compare-and-swap sobre
-- event_numbers con WHERE status='AVAILABLE'. El perdedor de la carrera afecta
-- 0 filas (no es un error de Postgres: es un resultado que hay que leer).
-- All-or-nothing: si algún número ya estaba tomado, no queda ningún hold.
-- ---------------------------------------------------------------------------
create or replace function public.reservation_create(
  p_event_id uuid,
  p_numbers  int[],
  p_terms_version_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := (select auth.uid());
  v_event      public.events;
  v_res_id     uuid := gen_random_uuid();
  v_is_anon    boolean;
  v_max        int;
  v_ttl        interval;
  v_review_ttl interval;
  v_aceptacion uuid;
  v_pedidos    int;
  v_afectadas  int;
  v_tomados    int[];
  v_previos    int;
  v_total      numeric(12,2);
  v_abuse      record;
begin
  -- 1) Sesión (anónima de Auth o registrada: las dos sirven).
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED',
      'message', 'Necesitás una sesión para reservar.');
  end if;

  -- 2) Perfil habilitado.
  if not exists (
    select 1 from public.profiles p where p.id = v_uid and p.status = 'ACTIVE'
  ) then
    return jsonb_build_object('ok', false, 'code', 'ACCOUNT_BLOCKED',
      'message', 'Tu cuenta no está habilitada para participar.');
  end if;

  -- 3) Evento y comercio.
  select * into v_event from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'EVENT_UNAVAILABLE',
      'message', 'El evento no existe.');
  end if;

  if not exists (
    select 1 from public.merchants m
     where m.id = v_event.merchant_id and m.status = 'ACTIVE'
  ) then
    return jsonb_build_object('ok', false, 'code', 'EVENT_UNAVAILABLE',
      'message', 'El comercio no está disponible.');
  end if;

  v_is_anon := private.is_anonymous_user();

  -- 4) Números pedidos: no vacío, sin duplicados y dentro del rango.
  v_pedidos := coalesce(array_length(p_numbers, 1), 0);
  if v_pedidos = 0 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_NUMBERS',
      'message', 'No seleccionaste ningún número.');
  end if;

  if (select count(*) from (select distinct unnest(p_numbers)) x) <> v_pedidos then
    return jsonb_build_object('ok', false, 'code', 'INVALID_NUMBERS',
      'message', 'La selección tiene números repetidos.');
  end if;

  if exists (
    select 1 from unnest(p_numbers) as n
     where n < v_event.numbers_from or n > v_event.numbers_to
  ) then
    return jsonb_build_object('ok', false, 'code', 'INVALID_NUMBERS',
      'message', 'Alguno de los números está fuera del rango del sorteo.');
  end if;

  -- 5) Ventana temporal y estado. EL RELOJ DEL SERVIDOR MANDA: el estado
  --    describe, no autoriza.
  if now() < v_event.starts_at then
    return jsonb_build_object('ok', false, 'code', 'EVENT_NOT_STARTED',
      'message', 'La participación todavía no empezó.');
  end if;

  if now() > v_event.participation_ends_at then
    return jsonb_build_object('ok', false, 'code', 'EVENT_CLOSED',
      'message', 'El plazo de participación ya venció.');
  end if;

  if v_event.status in ('CLOSED','DRAWN','CANCELLED') then
    return jsonb_build_object('ok', false, 'code', 'EVENT_CLOSED',
      'message', 'El evento ya no acepta reservas.',
      'details', jsonb_build_object('status', v_event.status));
  end if;

  if v_event.status not in ('PUBLISHED','OPEN') then
    return jsonb_build_object('ok', false, 'code', 'EVENT_NOT_OPEN',
      'message', 'El evento no está abierto.');
  end if;

  -- 6) REGLA DURA: el personal del comercio no participa en sus propios
  --    eventos. Se evalúa ACÁ, no en el navegador.
  if private.is_merchant_staff_of_event(p_event_id, v_uid) then
    return jsonb_build_object('ok', false, 'code', 'STAFF_CANNOT_PARTICIPATE',
      'message', 'Quienes trabajan en este comercio no pueden participar en sus propios sorteos.');
  end if;

  -- 7) Bloqueos vigentes.
  if private.is_blocked(v_uid, v_event.merchant_id, p_event_id) then
    return jsonb_build_object('ok', false, 'code', 'BLOCKED',
      'message', 'No podés participar en este momento.');
  end if;

  -- 8) Términos: tiene que existir la aceptación de la versión vigente.
  if not exists (
    select 1 from public.terms_versions tv
     where tv.id = p_terms_version_id
       and (
         tv.id = v_event.terms_version_id
         or (tv.scope = 'GLOBAL' and tv.kind = 'TERMS' and tv.is_current)
       )
  ) then
    return jsonb_build_object('ok', false, 'code', 'TERMS_VERSION_INVALID',
      'message', 'Las condiciones cambiaron. Volvé a leerlas y aceptalas.');
  end if;

  select ta.id into v_aceptacion
    from public.terms_acceptances ta
   where ta.profile_id = v_uid
     and ta.terms_version_id = p_terms_version_id
   limit 1;

  if v_aceptacion is null then
    return jsonb_build_object('ok', false, 'code', 'TERMS_NOT_ACCEPTED',
      'message', 'Tenés que aceptar las condiciones para reservar.');
  end if;

  -- 9) Límites efectivos (el evento acotado por el techo global del comercio).
  select l.max_numbers, l.ttl, l.review_ttl
    into v_max, v_ttl, v_review_ttl
    from private.fn_effective_limits(p_event_id, v_is_anon) l;

  if v_pedidos > v_max then
    return jsonb_build_object('ok', false, 'code', 'LIMIT_EXCEEDED',
      'message', format('Podés reservar hasta %s números por vez.', v_max),
      'details', jsonb_build_object('max', v_max, 'requested', v_pedidos));
  end if;

  -- 10) Tope por evento, contando lo que ya tiene reservado o pago.
  select coalesce(sum(r.number_count), 0) into v_previos
    from public.reservations r
   where r.event_id = p_event_id
     and r.profile_id = v_uid
     and r.status in ('PENDING','PAYMENT_SUBMITTED','APPROVED');

  if v_previos + v_pedidos > v_max then
    return jsonb_build_object('ok', false, 'code', 'EVENT_LIMIT_EXCEEDED',
      'message', format('Ya tenés %s números en este sorteo y el máximo es %s.',
                        v_previos, v_max),
      'details', jsonb_build_object('already', v_previos, 'max', v_max));
  end if;

  -- 11) Antiabuso: reservas simultáneas, rate limit, cooldown.
  select * into v_abuse
    from private.abuse_evaluate(v_uid, p_event_id, v_event.merchant_id, v_is_anon);

  if not v_abuse.allowed then
    return jsonb_build_object('ok', false, 'code', v_abuse.code,
      'message', 'No podés reservar en este momento. Probá más tarde.',
      'details', v_abuse.detail);
  end if;

  -- 12) Liberar holds vencidos de forma defensiva, para no depender del cron.
  perform public.reservations_expire_stale(200);

  v_total := round(v_event.price_per_number * v_pedidos, 2);

  -- 13) Reserva "cabeza" primero: el ledger y los números la referencian.
  insert into public.reservations (
    id, event_id, merchant_id, profile_id, status,
    number_count, unit_price, total_amount, currency,
    reserved_at, expires_at, terms_acceptance_id
  ) values (
    v_res_id, p_event_id, v_event.merchant_id, v_uid, 'PENDING',
    v_pedidos, v_event.price_per_number, v_total, v_event.currency,
    now(), now() + v_ttl, v_aceptacion
  );

  -- 14) EL CAS: una sola sentencia para TODOS los números pedidos.
  --     Los que ya tienen tenedor simplemente no se actualizan.
  with pedidos as (
    select unnest(p_numbers) as number
  ),
  actualizados as (
    update public.event_numbers en
       set status = 'RESERVED',
           reservation_id = v_res_id,
           updated_at = now()
     where en.event_id = p_event_id
       and en.number in (select number from pedidos)
       and en.status = 'AVAILABLE'
    returning en.id, en.number
  )
  insert into public.reservation_numbers
         (reservation_id, event_number_id, event_id, number, assigned_at)
  select v_res_id, id, p_event_id, number, now()
    from actualizados;

  get diagnostics v_afectadas = row_count;

  -- 15) Si no se obtuvieron TODOS, no queda nada a medias: se libera lo tomado
  --     y se responde con los números que se perdieron.
  if v_afectadas <> v_pedidos then
    select coalesce(array_agg(en.number order by en.number), '{}')
      into v_tomados
      from public.event_numbers en
     where en.event_id = p_event_id
       and en.number = any(p_numbers)
       and en.reservation_id is distinct from v_res_id;

    delete from public.reservation_numbers rn where rn.reservation_id = v_res_id;

    update public.event_numbers en
       set status = 'AVAILABLE', reservation_id = null, updated_at = now()
     where en.reservation_id = v_res_id;

    delete from public.reservations r where r.id = v_res_id;

    return jsonb_build_object('ok', false, 'code', 'NUMBER_TAKEN',
      'message', 'Alguno de los números ya no está disponible.',
      'details', jsonb_build_object('taken', to_jsonb(v_tomados)));
  end if;

  -- 16) Éxito: auditoría, notificación y respuesta.
  perform private.log_audit(
    'reservation.create', 'reservation', v_res_id, v_event.merchant_id, p_event_id,
    null,
    jsonb_build_object('numbers', p_numbers, 'total_amount', v_total, 'status', 'PENDING'),
    jsonb_build_object('is_anonymous', v_is_anon)
  );

  perform private.fn_notify(
    v_uid, 'reservation.created', 'Reserva registrada',
    format('Reservaste %s número(s). Tenés hasta el %s para subir el comprobante.',
           v_pedidos, to_char(now() + v_ttl, 'DD/MM/YYYY HH24:MI')),
    v_event.merchant_id, p_event_id, v_res_id,
    jsonb_build_object('expires_at', now() + v_ttl, 'numbers', p_numbers)
  );

  update public.profiles set last_seen_at = now() where id = v_uid;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'reservation_id', v_res_id,
    'numbers',        to_jsonb(p_numbers),
    'number_count',   v_pedidos,
    'unit_price',     v_event.price_per_number,
    'total_amount',   v_total,
    'currency',       v_event.currency,
    'expires_at',     now() + v_ttl
  ));
end $$;

comment on function public.reservation_create(uuid, int[], uuid) is
  'Reserva atomica con compare-and-swap sobre event_numbers. All-or-nothing: si un numero ya esta tomado no queda ningun hold parcial.';

-- ---------------------------------------------------------------------------
-- EXPIRAR HOLDS VENCIDOS
-- Idempotente y también CAS: si el participante subió el comprobante un segundo
-- antes, la fila ya no está en PENDING y no se toca.
-- La corre pg_cron cada minuto Y se invoca defensivamente en otras RPC.
-- ---------------------------------------------------------------------------
create or replace function public.reservations_expire_stale(p_limit int default 500)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids   uuid[];
  v_count int;
  v_id    uuid;
begin
  select array_agg(x.id)
    into v_ids
    from (
      select r.id
        from public.reservations r
       where r.status = 'PENDING'
         and r.expires_at < now()
       order by r.expires_at
       limit greatest(p_limit, 1)
       for update skip locked
    ) x;

  if v_ids is null or array_length(v_ids, 1) = 0 then
    return 0;
  end if;

  -- 1) Cerrar las asignaciones vigentes del ledger.
  update public.reservation_numbers rn
     set released_at = now(),
         release_reason = 'EXPIRED'
   where rn.reservation_id = any(v_ids)
     and rn.released_at is null;

  -- 2) Devolver los números a AVAILABLE (el CHECK exige reservation_id NULL).
  update public.event_numbers en
     set status = 'AVAILABLE',
         reservation_id = null,
         updated_at = now()
   where en.reservation_id = any(v_ids);

  -- 3) Cerrar las reservas.
  update public.reservations r
     set status = 'EXPIRED',
         closed_at = now(),
         expiration_reason = 'TTL_EXPIRED'
   where r.id = any(v_ids)
     and r.status = 'PENDING';

  get diagnostics v_count = row_count;

  -- 4) Auditoría y aviso, una por reserva.
  foreach v_id in array v_ids loop
    perform private.log_audit('reservation.expire', 'reservation', v_id,
      (select merchant_id from public.reservations where id = v_id),
      (select event_id    from public.reservations where id = v_id),
      jsonb_build_object('status', 'PENDING'),
      jsonb_build_object('status', 'EXPIRED', 'reason', 'TTL_EXPIRED'));

    perform private.fn_notify(
      (select profile_id from public.reservations where id = v_id),
      'reservation.expired', 'Tu reserva venció',
      'Se liberaron los números porque no se subió el comprobante a tiempo.',
      (select merchant_id from public.reservations where id = v_id),
      (select event_id    from public.reservations where id = v_id),
      v_id);
  end loop;

  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- CANCELAR UNA RESERVA
-- El dueño puede cancelar la suya mientras está PENDING. El staff con
-- reservation.cancel puede cancelar cualquiera de su comercio.
-- ---------------------------------------------------------------------------
create or replace function public.reservation_cancel(
  p_reservation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_r   public.reservations;
  v_es_staff boolean;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED',
      'message', 'Necesitás una sesión.');
  end if;

  select * into v_r from public.reservations r where r.id = p_reservation_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND',
      'message', 'La reserva no existe.');
  end if;

  v_es_staff := private.has_merchant_permission(v_r.merchant_id, 'reservation.cancel');

  if not (v_r.profile_id = v_uid or v_es_staff) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No podés cancelar esta reserva.');
  end if;

  if v_r.status <> 'PENDING' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Sólo se puede cancelar una reserva pendiente de pago.',
      'details', jsonb_build_object('status', v_r.status));
  end if;

  update public.reservation_numbers rn
     set released_at = now(),
         release_reason = 'CANCELLED'
   where rn.reservation_id = v_r.id
     and rn.released_at is null;

  update public.event_numbers en
     set status = 'AVAILABLE',
         reservation_id = null,
         updated_at = now()
   where en.reservation_id = v_r.id;

  update public.reservations r
     set status = 'CANCELLED',
         closed_at = now(),
         cancel_reason = coalesce(nullif(btrim(p_reason), ''), 'Cancelada por el usuario')
   where r.id = v_r.id;

  perform private.log_audit('reservation.cancel', 'reservation', v_r.id,
    v_r.merchant_id, v_r.event_id,
    jsonb_build_object('status', v_r.status),
    jsonb_build_object('status', 'CANCELLED', 'reason', p_reason),
    jsonb_build_object('by_staff', v_es_staff));

  if v_es_staff and v_r.profile_id <> v_uid then
    perform private.fn_notify(v_r.profile_id, 'reservation.cancelled',
      'Tu reserva fue cancelada',
      coalesce(p_reason, 'El comercio canceló la reserva.'),
      v_r.merchant_id, v_r.event_id, v_r.id);
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'reservation_id', v_r.id, 'status', 'CANCELLED'));
end $$;

-- ---------------------------------------------------------------------------
-- ADJUNTAR COMPROBANTE
-- El archivo ya se subió a Storage (bucket privado). Acá se registra la
-- METADATA y se valida que el path pertenezca de verdad a esta reserva: sin
-- esto, alguien podría registrar la metadata del comprobante de otro.
-- ---------------------------------------------------------------------------
create or replace function public.receipt_attach(
  p_reservation_id uuid,
  p_storage_path   text,
  p_original_name  text,
  p_mime_type      text,
  p_size_bytes     bigint,
  p_checksum       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := (select auth.uid());
  v_r        public.reservations;
  v_is_anon  boolean;
  v_max      int;
  v_ttl      interval;
  v_review   interval;
  v_prefix   text;
  v_receipt  uuid;
  v_recipient uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED',
      'message', 'Necesitás una sesión.');
  end if;

  select * into v_r from public.reservations r where r.id = p_reservation_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND',
      'message', 'La reserva no existe.');
  end if;

  -- SÓLO el dueño de la reserva puede subir su comprobante.
  if v_r.profile_id <> v_uid then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Esta reserva no es tuya.');
  end if;

  v_is_anon := private.is_anonymous_user();

  select l.max_numbers, l.ttl, l.review_ttl
    into v_max, v_ttl, v_review
    from private.fn_effective_limits(v_r.event_id, v_is_anon) l;

  -- Si el hold venció, se libera y se avisa (no se acepta un pago tardío
  -- sobre números que ya volvieron al mercado).
  if v_r.status = 'PENDING' and v_r.expires_at <= now() then
    perform public.reservations_expire_stale(500);
    select * into v_r from public.reservations r where r.id = p_reservation_id;
  end if;

  if v_r.status <> 'PENDING' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', case
                   when v_r.status = 'EXPIRED' then 'Tu reserva venció y los números se liberaron.'
                   when v_r.status = 'PAYMENT_SUBMITTED' then 'Ya hay un comprobante en revisión.'
                   when v_r.status = 'APPROVED' then 'Tu pago ya está aprobado.'
                   else 'La reserva no admite comprobantes en este estado.'
                 end,
      'details', jsonb_build_object('status', v_r.status));
  end if;

  -- El path TIENE que estar bajo la carpeta de esta reserva.
  v_prefix := v_r.merchant_id::text || '/' || v_r.event_id::text || '/' || v_r.id::text || '/';
  if p_storage_path is null or left(p_storage_path, length(v_prefix)) <> v_prefix then
    return jsonb_build_object('ok', false, 'code', 'INVALID_PATH',
      'message', 'La ruta del archivo no corresponde a esta reserva.');
  end if;

  if p_mime_type not in ('image/jpeg','image/png','image/webp','application/pdf') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_FILE_TYPE',
      'message', 'Formato no permitido. Se aceptan JPG, PNG, WEBP o PDF.');
  end if;

  if p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > 8388608 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_FILE_SIZE',
      'message', 'El archivo tiene que pesar entre 1 byte y 8 MB.');
  end if;

  if exists (
    select 1 from public.payment_receipts pr
     where pr.reservation_id = v_r.id and pr.status = 'PENDING'
  ) then
    return jsonb_build_object('ok', false, 'code', 'RECEIPT_ALREADY_PENDING',
      'message', 'Ya hay un comprobante en revisión para esta reserva.');
  end if;

  insert into public.payment_receipts (
    reservation_id, merchant_id, event_id, uploaded_by,
    storage_path, original_name, mime_type, size_bytes, checksum_sha256, status
  ) values (
    v_r.id, v_r.merchant_id, v_r.event_id, v_uid,
    p_storage_path, p_original_name, p_mime_type, p_size_bytes, p_checksum, 'PENDING'
  )
  returning id into v_receipt;

  update public.event_numbers en
     set status = 'PAYMENT_SUBMITTED', updated_at = now()
   where en.reservation_id = v_r.id;

  update public.reservations r
     set status = 'PAYMENT_SUBMITTED',
         payment_submitted_at = now(),
         review_deadline_at = now() + v_review
   where r.id = v_r.id;

  perform private.log_audit('receipt.submit', 'payment_receipt', v_receipt,
    v_r.merchant_id, v_r.event_id, null,
    jsonb_build_object('status', 'PENDING', 'mime_type', p_mime_type, 'size_bytes', p_size_bytes),
    jsonb_build_object('reservation_id', v_r.id));

  perform private.fn_notify(v_uid, 'payment.receipt.submitted', 'Comprobante recibido',
    'Lo estamos revisando. Te avisamos cuando esté validado.',
    v_r.merchant_id, v_r.event_id, v_r.id);

  -- Aviso al comercio: sólo a los MERCHANT (tienen el permiso de revisión).
  for v_recipient in
    select mm.profile_id
      from public.merchant_members mm
     where mm.merchant_id = v_r.merchant_id
       and mm.status = 'ACTIVE'
       and mm.role = 'MERCHANT'
  loop
    perform private.fn_notify(v_recipient, 'payment.receipt.submitted',
      'Nuevo comprobante para revisar',
      format('Reserva con %s número(s) por %s %s.',
             v_r.number_count, v_r.currency, v_r.total_amount),
      v_r.merchant_id, v_r.event_id, v_r.id);
  end loop;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'receipt_id', v_receipt,
    'reservation_id', v_r.id,
    'status', 'PAYMENT_SUBMITTED',
    'review_deadline_at', now() + v_review));
end $$;

-- ---------------------------------------------------------------------------
-- REVISAR COMPROBANTE
-- Único camino para aprobar o rechazar. El participante NO puede aprobarse:
-- no tiene grant de UPDATE sobre payment_receipts ni policy que lo permita.
-- ---------------------------------------------------------------------------
create or replace function public.review_receipt(
  p_receipt_id uuid,
  p_decision   text,          -- 'APPROVE' | 'REJECT' | 'REQUEST_CORRECTION'
  p_reason     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_rec     public.payment_receipts;
  v_r       public.reservations;
  v_is_anon boolean;
  v_ttl     interval;
  v_review  interval;
  v_max     int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED',
      'message', 'Necesitás una sesión.');
  end if;

  if p_decision not in ('APPROVE','REJECT','REQUEST_CORRECTION') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_DECISION',
      'message', 'Decisión inválida.');
  end if;

  select * into v_rec from public.payment_receipts pr where pr.id = p_receipt_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND',
      'message', 'El comprobante no existe.');
  end if;

  -- Permiso de revisión DENTRO de ese comercio (nunca de otro).
  if not ((select private.is_owner())
          or private.has_merchant_permission(v_rec.merchant_id, 'payment.receipt.review')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para revisar comprobantes de este comercio.');
  end if;

  -- Nadie revisa su propio comprobante, ni el de su propia reserva.
  if v_rec.uploaded_by = v_uid then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No podés revisar tu propio comprobante.');
  end if;

  select * into v_r from public.reservations r where r.id = v_rec.reservation_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND',
      'message', 'La reserva del comprobante no existe.');
  end if;

  if v_r.profile_id = v_uid then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No podés revisar el comprobante de tu propia reserva.');
  end if;

  if v_rec.status <> 'PENDING' then
    return jsonb_build_object('ok', false, 'code', 'ALREADY_REVIEWED',
      'message', 'Este comprobante ya fue revisado.',
      'details', jsonb_build_object('status', v_rec.status));
  end if;

  if p_decision in ('REJECT','REQUEST_CORRECTION')
     and (p_reason is null or char_length(btrim(p_reason)) < 5) then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indicá el motivo (mínimo 5 caracteres).');
  end if;

  select p.is_anonymous into v_is_anon from public.profiles p where p.id = v_r.profile_id;

  select l.max_numbers, l.ttl, l.review_ttl
    into v_max, v_ttl, v_review
    from private.fn_effective_limits(v_r.event_id, coalesce(v_is_anon, false)) l;

  if p_decision = 'APPROVE' then
    update public.payment_receipts pr
       set status = 'APPROVED',
           reviewed_by = v_uid,
           reviewed_at = now(),
           review_reason = nullif(btrim(coalesce(p_reason, '')), '')
     where pr.id = v_rec.id;

    update public.event_numbers en
       set status = 'PAID', updated_at = now()
     where en.reservation_id = v_r.id;

    update public.reservations r
       set status = 'APPROVED',
           approved_at = now(),
           review_note = nullif(btrim(coalesce(p_reason, '')), '')
     where r.id = v_r.id;

    perform private.log_audit('receipt.approve', 'payment_receipt', v_rec.id,
      v_rec.merchant_id, v_rec.event_id,
      jsonb_build_object('status', 'PENDING'),
      jsonb_build_object('status', 'APPROVED'),
      jsonb_build_object('reservation_id', v_r.id, 'total_amount', v_r.total_amount));

    perform private.fn_notify(v_r.profile_id, 'payment.receipt.approved',
      '¡Pago confirmado!',
      format('Tus %s número(s) quedaron confirmados.', v_r.number_count),
      v_rec.merchant_id, v_rec.event_id, v_r.id);

    return jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'receipt_id', v_rec.id, 'receipt_status', 'APPROVED',
      'reservation_status', 'APPROVED'));
  end if;

  if p_decision = 'REJECT' then
    update public.payment_receipts pr
       set status = 'REJECTED',
           reviewed_by = v_uid,
           reviewed_at = now(),
           review_reason = 'RECHAZO DEFINITIVO: ' || btrim(p_reason)
     where pr.id = v_rec.id;

    -- Se liberan los números: el pago no se acreditó.
    update public.reservation_numbers rn
       set released_at = now(), release_reason = 'REJECTED'
     where rn.reservation_id = v_r.id
       and rn.released_at is null;

    update public.event_numbers en
       set status = 'AVAILABLE', reservation_id = null, updated_at = now()
     where en.reservation_id = v_r.id;

    update public.reservations r
       set status = 'REJECTED',
           closed_at = now(),
           review_note = btrim(p_reason),
           rejection_count = r.rejection_count + 1
     where r.id = v_r.id;

    perform private.log_audit('receipt.reject', 'payment_receipt', v_rec.id,
      v_rec.merchant_id, v_rec.event_id,
      jsonb_build_object('status', 'PENDING'),
      jsonb_build_object('status', 'REJECTED', 'reason', btrim(p_reason)),
      jsonb_build_object('reservation_id', v_r.id));

    perform private.fn_notify(v_r.profile_id, 'payment.receipt.rejected',
      'Comprobante rechazado', btrim(p_reason),
      v_rec.merchant_id, v_rec.event_id, v_r.id);

    return jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'receipt_id', v_rec.id, 'receipt_status', 'REJECTED',
      'reservation_status', 'REJECTED'));
  end if;

  -- REQUEST_CORRECTION: la vía amable. El comprobante se cierra como REJECTED
  -- (con motivo tipado) y la reserva VUELVE A PENDING con un nuevo plazo: el
  -- participante no pierde los números por un error subsanable.
  update public.payment_receipts pr
     set status = 'REJECTED',
         reviewed_by = v_uid,
         reviewed_at = now(),
         review_reason = 'CORRECCION SOLICITADA: ' || btrim(p_reason)
   where pr.id = v_rec.id;

  update public.event_numbers en
     set status = 'RESERVED', updated_at = now()
   where en.reservation_id = v_r.id;

  update public.reservations r
     set status = 'PENDING',
         expires_at = now() + v_ttl,
         review_deadline_at = null,
         review_note = btrim(p_reason),
         rejection_count = r.rejection_count + 1
   where r.id = v_r.id;

  perform private.log_audit('receipt.request_correction', 'payment_receipt', v_rec.id,
    v_rec.merchant_id, v_rec.event_id,
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', 'REJECTED', 'reason', 'CORRECCION SOLICITADA'),
    jsonb_build_object('reservation_id', v_r.id));

  perform private.fn_notify(v_r.profile_id, 'payment.correction_requested',
    'Necesitamos que corrijas el comprobante',
    format('%s — Tenés tiempo hasta el %s.',
           btrim(p_reason), to_char(now() + v_ttl, 'DD/MM/YYYY HH24:MI')),
    v_rec.merchant_id, v_rec.event_id, v_r.id);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'receipt_id', v_rec.id, 'receipt_status', 'REJECTED',
    'reservation_status', 'PENDING', 'expires_at', now() + v_ttl));
end $$;

-- ---------------------------------------------------------------------------
-- GRANTS: las RPC son la única puerta de escritura.
-- reservations_expire_stale queda INTERNA (la llama el cron y las otras RPC,
-- que son security definer). Ningún cliente la invoca directamente.
-- ---------------------------------------------------------------------------
revoke all on function public.reservation_create(uuid, int[], uuid) from public, anon;
revoke all on function public.reservation_cancel(uuid, text)        from public, anon;
revoke all on function public.receipt_attach(uuid, text, text, text, bigint, text) from public, anon;
revoke all on function public.review_receipt(uuid, text, text)      from public, anon;
revoke all on function public.reservations_expire_stale(int)        from public, anon, authenticated;

grant execute on function public.reservation_create(uuid, int[], uuid) to authenticated;
grant execute on function public.reservation_cancel(uuid, text)        to authenticated;
grant execute on function public.receipt_attach(uuid, text, text, text, bigint, text) to authenticated;
grant execute on function public.review_receipt(uuid, text, text)      to authenticated;
grant execute on function public.reservations_expire_stale(int)        to service_role;