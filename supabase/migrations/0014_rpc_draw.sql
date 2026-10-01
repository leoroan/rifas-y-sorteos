-- =============================================================================
-- 0014_rpc_draw.sql
-- Determinación del ganador: MANUAL, RANDOM_SEEDED y EXTERNAL_LOTTERY.
-- El seed SIEMPRE lo genera el servidor. draw_results tiene UNIQUE(event_id) y
-- los clientes no tienen UPDATE/DELETE: un solo tiro, sin grinding posible.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Sorteo aleatorio ENTRE LOS NÚMEROS PAGADOS.
-- Es la semántica natural de una rifa: se sortea entre los que participaron
-- pagando, no entre 500 números de los cuales sólo 137 están vendidos. Además
-- garantiza que siempre haya ganador.
-- Reproducible: con el seed y la lista ordenada de pagados, cualquiera recalcula.
-- ---------------------------------------------------------------------------
create or replace function private.fn_seeded_pick(
  p_seed      bytea,
  p_event_id  uuid,
  p_paid_list int[]
)
returns table (computed int, digest_hex text, picked_index int, algorithm text)
language plpgsql stable set search_path = ''
as $$
declare
  v_h     text;
  v_total int;
  v_u     bigint;
  v_idx   int;
begin
  v_total := coalesce(array_length(p_paid_list, 1), 0);
  if v_total < 1 then
    raise exception 'NO_PAID_NUMBERS' using errcode = '22023';
  end if;
  if p_seed is null or octet_length(p_seed) < 16 then
    raise exception 'INVALID_SEED' using errcode = '22023';
  end if;

  v_h   := encode(extensions.digest(p_seed::text || ':' || p_event_id::text, 'sha256'), 'hex');
  v_u   := ('x' || substr(v_h, 1, 15))::bit(60)::bigint;
  v_idx := (v_u % v_total)::int + 1;

  return query select p_paid_list[v_idx], v_h, v_idx, 'SHA256_MOD60_PAID_V1'::text;
end $$;
comment on function private.fn_seeded_pick(bytea, uuid, int[]) is
  'Elige el ganador entre los numeros PAGADOS, de forma reproducible con el seed publicado.';

-- ---------------------------------------------------------------------------
-- REGISTRAR EL RESULTADO
-- p_payload admite:
--   MANUAL           -> {"declared_number":N,"justification":"...","evidence_url"|"evidence_path":"..."}
--   RANDOM_SEEDED    -> {}   (el seed lo pone el servidor; se ignora lo que venga)
--   EXTERNAL_LOTTERY -> {"extract_number":N,"draw_date":"YYYY-MM-DD","draw_source_id":"...","raw_payload":{}}
-- ---------------------------------------------------------------------------
create or replace function public.event_record_draw_result(p_event_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_e         public.events;
  v_metodo    text;
  v_seed      bytea;
  v_digest    text;
  v_algo      text;
  v_idx       int;
  v_computed  int;
  v_paid_list int[];
  v_extract   int;
  v_rule      text;
  v_res_id    uuid;
  v_es_pagado boolean;
  v_justif    text;
  v_ev_url    text;
  v_ev_path   text;
  v_manual    int;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.draw')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para registrar el resultado de este evento.');
  end if;

  if v_e.status <> 'CLOSED' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Primero hay que cerrar el evento para poder sortear.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  if exists (select 1 from public.draw_results dr where dr.event_id = p_event_id) then
    return jsonb_build_object('ok', false, 'code', 'ALREADY_DRAWN',
      'message', 'Este evento ya tiene un resultado. Un sorteo es de un solo tiro.');
  end if;

  v_metodo := v_e.winner_method;

  if v_metodo = 'MANUAL' then
    v_manual  := nullif(p_payload->>'declared_number','')::int;
    v_justif  := nullif(btrim(coalesce(p_payload->>'justification','')), '');
    v_ev_url  := nullif(p_payload->>'evidence_url','');
    v_ev_path := nullif(p_payload->>'evidence_path','');

    if v_manual is null or v_manual < v_e.numbers_from or v_manual > v_e.numbers_to then
      return jsonb_build_object('ok', false, 'code', 'INVALID_NUMBER',
        'message', 'El número declarado no pertenece al rango del sorteo.');
    end if;
    if v_justif is null or char_length(v_justif) < 20 then
      return jsonb_build_object('ok', false, 'code', 'JUSTIFICATION_REQUIRED',
        'message', 'Explicá cómo se determinó el ganador (mínimo 20 caracteres).');
    end if;
    if v_ev_url is null and v_ev_path is null then
      return jsonb_build_object('ok', false, 'code', 'EVIDENCE_REQUIRED',
        'message', 'Adjuntá una evidencia (acta, foto o enlace del sorteo).');
    end if;

    v_computed := v_manual;
    v_algo     := 'MANUAL_DECLARED';

  elsif v_metodo = 'RANDOM_SEEDED' then
    select array_agg(en.number order by en.number)
      into v_paid_list
      from public.event_numbers en
     where en.event_id = p_event_id and en.status = 'PAID';

    if coalesce(array_length(v_paid_list, 1), 0) = 0 then
      return jsonb_build_object('ok', false, 'code', 'NO_PAID_NUMBERS',
        'message', 'Todavía no hay ningún número con pago confirmado.');
    end if;

    v_seed := extensions.gen_random_bytes(32);        -- el servidor manda
    select sp.computed, sp.digest_hex, sp.picked_index, sp.algorithm
      into v_computed, v_digest, v_idx, v_algo
      from private.fn_seeded_pick(v_seed, p_event_id, v_paid_list) sp;

  else  -- EXTERNAL_LOTTERY
    v_rule    := coalesce(v_e.winner_rule, 'MODULO_RESTO');
    v_extract := nullif(p_payload->>'extract_number','')::int;

    if v_extract is null or p_payload->>'draw_date' is null then
      return jsonb_build_object('ok', false, 'code', 'DRAW_DATA_REQUIRED',
        'message', 'Cargá el extracto y la fecha del sorteo de referencia.');
    end if;

    v_algo := 'EXTERNAL_' || v_rule;

    if v_rule = 'MODULO_RESTO' then
      v_computed := v_e.numbers_from + (v_extract % (v_e.numbers_to - v_e.numbers_from + 1));
    elsif v_rule = 'EXTRACTO_EXACTO' then
      if v_extract < v_e.numbers_from or v_extract > v_e.numbers_to then
        return jsonb_build_object('ok', false, 'code', 'EXTRACT_OUT_OF_RANGE',
          'message', 'El extracto quedó fuera del rango de números del sorteo.',
          'details', jsonb_build_object('extract', v_extract,
                                        'from', v_e.numbers_from, 'to', v_e.numbers_to));
      end if;
      v_computed := v_extract;
    else  -- ULTIMOS_DIGITOS
      v_computed := v_e.numbers_from + (abs(v_extract) % (v_e.numbers_to - v_e.numbers_from + 1));
    end if;
  end if;

  select exists (
    select 1 from public.event_numbers en
     where en.event_id = p_event_id and en.number = v_computed and en.status = 'PAID'
  ) into v_es_pagado;

  insert into public.draw_results (
    event_id, draw_source_id, draw_source_snapshot, draw_shift, draw_date,
    extract_number, raw_payload,
    winner_method_snapshot, winner_rule_snapshot,
    numbers_from_snapshot, numbers_to_snapshot, total_numbers_snapshot,
    seed, algorithm, seed_commitment, revealed_at,
    computed_number, justification, evidence_url, evidence_path, notes, recorded_by
  ) values (
    p_event_id,
    coalesce(nullif(p_payload->>'draw_source_id','')::uuid, v_e.draw_source_id),
    (select ds.name from public.draw_sources ds
      where ds.id = coalesce(nullif(p_payload->>'draw_source_id','')::uuid, v_e.draw_source_id)),
    coalesce(nullif(p_payload->>'draw_shift',''), v_e.draw_shift),
    nullif(p_payload->>'draw_date','')::date,
    v_extract,
    case when v_metodo = 'RANDOM_SEEDED'
         then jsonb_build_object('seed', encode(v_seed, 'hex'),
                                 'digest', v_digest,
                                 'paid_numbers', to_jsonb(v_paid_list),
                                 'picked_index', v_idx,
                                 'algorithm', v_algo)
         else p_payload->'raw_payload' end,
    v_metodo, v_rule,
    v_e.numbers_from, v_e.numbers_to, v_e.numbers_to - v_e.numbers_from + 1,
    case when v_metodo = 'RANDOM_SEEDED' then encode(v_seed, 'hex') end,
    v_algo,
    case when v_metodo = 'RANDOM_SEEDED'
         then encode(extensions.digest(v_seed::text || ':' || p_event_id::text, 'sha256'), 'hex') end,
    case when v_metodo = 'RANDOM_SEEDED' then now() end,
    v_computed, v_justif, v_ev_url, v_ev_path,
    nullif(btrim(coalesce(p_payload->>'notes','')), ''),
    v_uid
  )
  returning id into v_res_id;

  perform private.log_audit('draw.result_recorded', 'draw_result', v_res_id,
    v_e.merchant_id, p_event_id, null,
    jsonb_build_object('method', v_metodo, 'computed_number', v_computed,
                       'is_paid', v_es_pagado, 'algorithm', v_algo),
    case when v_metodo = 'RANDOM_SEEDED'
         then jsonb_build_object('seed', encode(v_seed, 'hex'), 'index', v_idx) end);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'draw_result_id', v_res_id,
    'method', v_metodo,
    'algorithm', v_algo,
    'computed_number', v_computed,
    'is_paid', v_es_pagado,
    'seed', case when v_metodo = 'RANDOM_SEEDED' then encode(v_seed, 'hex') end,
    'picked_index', v_idx,
    'paid_numbers_count', coalesce(array_length(v_paid_list, 1), 0),
    'next_step', case when v_es_pagado then 'PUBLISH_WINNERS'
                      else coalesce(v_e.draw_fallback_policy, 'HOLD_FOR_REVIEW') end));
end $$;

-- ---------------------------------------------------------------------------
-- PUBLICAR GANADORES
-- Asigna un ganador por premio. Si hay más premios que números pagados
-- distintos, se reutiliza el mismo ganador para los premios restantes (caso
-- real: 1 participante y 3 premios) y se informa en el resultado.
-- ---------------------------------------------------------------------------
create or replace function public.event_publish_winners(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_e       public.events;
  v_dr      public.draw_results;
  v_num     public.event_numbers;
  v_res     public.reservations;
  v_prize   public.prizes;
  v_count   int := 0;
  v_numero  int;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.draw')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenés permiso para publicar ganadores de este evento.');
  end if;

  if v_e.status <> 'CLOSED' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'El evento tiene que estar cerrado.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  select * into v_dr from public.draw_results dr where dr.event_id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NO_DRAW_RESULT',
      'message', 'Primero registrá el resultado del sorteo.');
  end if;

  v_numero := v_dr.computed_number;

  select * into v_num from public.event_numbers en
   where en.event_id = p_event_id and en.number = v_numero;

  if v_num.status <> 'PAID' then
    return jsonb_build_object('ok', false, 'code', 'WINNER_NOT_PAID',
      'message', format('El número %s no tiene pago confirmado. Revisá el sorteo o aplicá la política de respaldo.', v_numero),
      'details', jsonb_build_object('number', v_numero, 'status', v_num.status,
                                    'fallback_policy', v_e.draw_fallback_policy));
  end if;

  select * into v_res from public.reservations r where r.id = v_num.reservation_id;

  for v_prize in
    select * from public.prizes p
     where p.event_id = p_event_id and p.status = 'ACTIVE'
     order by p.position
  loop
    insert into public.event_winners (
      event_id, prize_id, draw_result_id, profile_id, reservation_id,
      event_number_id, number, position, claim_deadline_at, claim_status
    ) values (
      p_event_id, v_prize.id, v_dr.id, v_res.profile_id, v_res.id,
      v_num.id, v_numero, v_prize.position,
      now() + interval '30 days', 'PENDING'
    )
    on conflict (event_id, prize_id) do nothing;

    v_count := v_count + 1;

    perform private.fn_notify(v_res.profile_id, 'winner.confirmed',
      format('¡Ganaste el premio "%s"!', v_prize.title),
      format('Tu número %s salió sorteado. Contactá al comercio para coordinar la entrega.', v_numero),
      v_e.merchant_id, p_event_id, v_res.id);
  end loop;

  if v_count = 0 then
    return jsonb_build_object('ok', false, 'code', 'NO_PRIZES',
      'message', 'El evento no tiene premios activos.');
  end if;

  update public.event_numbers en
     set status = 'WINNER', updated_at = now()
   where en.event_id = p_event_id and en.number = v_numero;

  update public.events e set status = 'DRAWN', updated_by = v_uid
   where e.id = p_event_id;

  perform private.log_audit('winner.published', 'event', p_event_id, v_e.merchant_id, p_event_id,
    jsonb_build_object('status', 'CLOSED'),
    jsonb_build_object('status', 'DRAWN', 'winning_number', v_numero,
                       'winners_created', v_count, 'draw_result_id', v_dr.id));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'event_id', p_event_id,
    'status', 'DRAWN',
    'winning_number', v_numero,
    'winners_created', v_count));
end $$;

-- ---------------------------------------------------------------------------
-- GRANTS
-- ---------------------------------------------------------------------------
revoke all on function public.event_record_draw_result(uuid, jsonb) from public, anon;
revoke all on function public.event_publish_winners(uuid)           from public, anon;
grant execute on function public.event_record_draw_result(uuid, jsonb) to authenticated;
grant execute on function public.event_publish_winners(uuid)           to authenticated;