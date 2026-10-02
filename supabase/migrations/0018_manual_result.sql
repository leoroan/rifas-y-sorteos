-- =============================================================================
-- 0018_manual_result.sql
-- Resultado cargado A MANO por el comerciante, con un numero ganador POR PREMIO.
--
-- Por que este archivo existe: no hay forma de automatizar la lectura del
-- resultado de una loteria, asi que el flujo real es que el comerciante carga
-- el resultado cuando el evento vence. Y con varios premios hace falta un
-- numero por puesto (1ro, 2do, 3ro... segun la config del evento).
--
-- Cambios de diseno respecto de 0014:
--  1) MANUAL acepta declared_numbers (array, uno por premio) o declared_number.
--  2) El resultado MANUAL se puede CORREGIR mientras el evento siga CLOSED.
--     El "un solo tiro" se conserva para RANDOM_SEEDED y EXTERNAL_LOTTERY: ahi
--     protege contra reintentar hasta obtener un ganador conveniente. En la
--     carga manual no protege nada (el comerciante declara lo que quiere igual)
--     y un error de tipeo no puede arruinar un evento para siempre.
--  3) publish_winners asigna un numero POR PREMIO cuando hay varios declarados.
-- =============================================================================

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
  v_nums      int[];
  v_existe    boolean;
  v_ya        public.draw_results;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.draw')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenes permiso para registrar el resultado de este evento.');
  end if;

  if v_e.status <> 'CLOSED' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'Primero hay que cerrar el evento para poder sortear.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  v_metodo := v_e.winner_method;

  -- ¿Ya hay resultado registrado?
  select * into v_ya from public.draw_results dr where dr.event_id = p_event_id;
  v_existe := found;

  if v_existe then
    -- Publicado = final. Nada se toca.
    if v_e.status = 'DRAWN' then
      return jsonb_build_object('ok', false, 'code', 'ALREADY_DRAWN',
        'message', 'Este evento ya tiene un resultado publicado.');
    end if;
    -- MANUAL se puede corregir mientras siga CLOSED (error de tipeo, etc.).
    -- RANDOM_SEEDED y EXTERNAL_LOTTERY siguen siendo de un solo tiro: ahi el
    -- "un solo tiro" es lo que impide reintentar hasta obtener un ganador.
    if v_metodo <> 'MANUAL' then
      return jsonb_build_object('ok', false, 'code', 'ALREADY_DRAWN',
        'message', 'Este evento ya tiene un resultado registrado. Un sorteo es de un solo tiro.');
    end if;
  end if;

  if v_metodo = 'MANUAL' then
    v_manual := nullif(p_payload->>'declared_number', '')::int;

    -- Array: un numero ganador por puesto, ordenado por posicion de premio.
    select coalesce(array_agg(t.value::int order by t.ord), '{}')
      into v_nums
      from jsonb_array_elements_text(coalesce(p_payload->'declared_numbers', '[]'::jsonb))
           with ordinality as t(value, ord);

    if array_length(v_nums, 1) > 0 then
      v_manual := v_nums[1];
    end if;

    if v_manual is null or v_manual < v_e.numbers_from or v_manual > v_e.numbers_to then
      return jsonb_build_object('ok', false, 'code', 'INVALID_NUMBER',
        'message', 'El numero declarado no pertenece al rango del sorteo.');
    end if;

    -- Todos los numeros declarados deben tener pago confirmado.
    if array_length(v_nums, 1) > 0 then
      select bool_and(en.status = 'PAID')
        into v_es_pagado
        from public.event_numbers en
       where en.event_id = p_event_id
         and en.number = any(v_nums);
      if coalesce(v_es_pagado, false) = false then
        return jsonb_build_object('ok', false, 'code', 'WINNER_NOT_PAID',
          'message', 'Alguno de los numeros declarados no tiene pago confirmado.');
      end if;
    end if;

    v_justif  := nullif(btrim(coalesce(p_payload->>'justification', '')), '');
    v_ev_url  := nullif(p_payload->>'evidence_url', '');
    v_ev_path := nullif(p_payload->>'evidence_path', '');

    if v_justif is null or char_length(v_justif) < 20 then
      return jsonb_build_object('ok', false, 'code', 'JUSTIFICATION_REQUIRED',
        'message', 'Explica como se determino el ganador (minimo 20 caracteres).');
    end if;
    if v_ev_url is null and v_ev_path is null then
      return jsonb_build_object('ok', false, 'code', 'EVIDENCE_REQUIRED',
        'message', 'Adjunta una evidencia (acta, foto o enlace del sorteo).');
    end if;

    v_computed := v_manual;
    v_algo     := 'MANUAL_DECLARED';

  elsif v_metodo = 'RANDOM_SEEDED' then
    if v_existe then
      return jsonb_build_object('ok', false, 'code', 'ALREADY_DRAWN',
        'message', 'Este evento ya tiene un resultado. Un sorteo es de un solo tiro.');
    end if;

    select array_agg(en.number order by en.number)
      into v_paid_list
      from public.event_numbers en
     where en.event_id = p_event_id and en.status = 'PAID';

    if coalesce(array_length(v_paid_list, 1), 0) = 0 then
      return jsonb_build_object('ok', false, 'code', 'NO_PAID_NUMBERS',
        'message', 'Todavia no hay ningun numero con pago confirmado.');
    end if;

    v_seed := extensions.gen_random_bytes(32);
    select sp.computed, sp.digest_hex, sp.picked_index, sp.algorithm
      into v_computed, v_digest, v_idx, v_algo
      from private.fn_seeded_pick(v_seed, p_event_id, v_paid_list) sp;

  else  -- EXTERNAL_LOTTERY
    if v_existe then
      return jsonb_build_object('ok', false, 'code', 'ALREADY_DRAWN',
        'message', 'Este evento ya tiene un resultado. Un sorteo es de un solo tiro.');
    end if;

    v_rule    := coalesce(v_e.winner_rule, 'MODULO_RESTO');
    v_extract := nullif(p_payload->>'extract_number', '')::int;

    if v_extract is null or p_payload->>'draw_date' is null then
      return jsonb_build_object('ok', false, 'code', 'DRAW_DATA_REQUIRED',
        'message', 'Carga el extracto y la fecha del sorteo de referencia.');
    end if;

    v_algo := 'EXTERNAL_' || v_rule;

    if v_rule = 'MODULO_RESTO' then
      v_computed := v_e.numbers_from + (v_extract % (v_e.numbers_to - v_e.numbers_from + 1));
    elsif v_rule = 'EXTRACTO_EXACTO' then
      if v_extract < v_e.numbers_from or v_extract > v_e.numbers_to then
        return jsonb_build_object('ok', false, 'code', 'EXTRACT_OUT_OF_RANGE',
          'message', 'El extracto quedo fuera del rango de numeros del sorteo.',
          'details', jsonb_build_object('extract', v_extract,
                                        'from', v_e.numbers_from, 'to', v_e.numbers_to));
      end if;
      v_computed := v_extract;
    else
      v_computed := v_e.numbers_from + (abs(v_extract) % (v_e.numbers_to - v_e.numbers_from + 1));
    end if;
  end if;

  select exists (
    select 1 from public.event_numbers en
     where en.event_id = p_event_id and en.number = v_computed and en.status = 'PAID'
  ) into v_es_pagado;

  -- MANUAL con varios numeros: el primero (puesto 1) tiene que estar pago.
  -- Los demas ya se validaron arriba.
  if v_metodo <> 'MANUAL' and not v_es_pagado then
    v_es_pagado := false;
  end if;

  if v_existe then
    -- Correccion de un resultado MANUAL todavia no publicado.
    update public.draw_results dr
       set extract_number = v_extract,
           raw_payload    = case when v_metodo = 'MANUAL'
                                  then jsonb_build_object('declared_numbers', to_jsonb(v_nums),
                                                          'algorithm', v_algo)
                                  else p_payload->'raw_payload' end,
           winner_method_snapshot = v_metodo,
           winner_rule_snapshot   = v_rule,
           numbers_from_snapshot = v_e.numbers_from,
           numbers_to_snapshot   = v_e.numbers_to,
           total_numbers_snapshot = v_e.numbers_to - v_e.numbers_from + 1,
           computed_number = v_computed,
           justification   = v_justif,
           evidence_url    = v_ev_url,
           evidence_path   = v_ev_path,
           recorded_by     = v_uid,
           recorded_at     = now()
     where dr.event_id = p_event_id
    returning id into v_res_id;
  else
    insert into public.draw_results (
      event_id, draw_source_id, draw_source_snapshot, draw_shift, draw_date,
      extract_number, raw_payload,
      winner_method_snapshot, winner_rule_snapshot,
      numbers_from_snapshot, numbers_to_snapshot, total_numbers_snapshot,
      seed, algorithm, seed_commitment, revealed_at,
      computed_number, justification, evidence_url, evidence_path, notes, recorded_by
    ) values (
      p_event_id,
      coalesce(nullif(p_payload->>'draw_source_id', '')::uuid, v_e.draw_source_id),
      (select ds.name from public.draw_sources ds
        where ds.id = coalesce(nullif(p_payload->>'draw_source_id', '')::uuid, v_e.draw_source_id)),
      coalesce(nullif(p_payload->>'draw_shift', ''), v_e.draw_shift),
      nullif(p_payload->>'draw_date', '')::date,
      v_extract,
      case when v_metodo = 'MANUAL'
           then jsonb_build_object('declared_numbers', to_jsonb(v_nums), 'algorithm', v_algo)
           else p_payload->'raw_payload' end,
      v_metodo, v_rule,
      v_e.numbers_from, v_e.numbers_to, v_e.numbers_to - v_e.numbers_from + 1,
      case when v_metodo = 'RANDOM_SEEDED' then encode(v_seed, 'hex') end,
      v_algo,
      case when v_metodo = 'RANDOM_SEEDED'
           then encode(extensions.digest(v_seed::text || ':' || p_event_id::text, 'sha256'), 'hex') end,
      case when v_metodo = 'RANDOM_SEEDED' then now() end,
      v_computed, v_justif, v_ev_url, v_ev_path,
      nullif(btrim(coalesce(p_payload->>'notes', '')), ''),
      v_uid
    )
    returning id into v_res_id;
  end if;

  perform private.log_audit(
    case when v_existe then 'draw.result_corrected' else 'draw.result_recorded' end,
    'draw_result', v_res_id, v_e.merchant_id, p_event_id, null,
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
    'declared_numbers', to_jsonb(v_nums),
    'seed', case when v_metodo = 'RANDOM_SEEDED' then encode(v_seed, 'hex') end,
    'picked_index', v_idx,
    'paid_numbers_count', coalesce(array_length(v_paid_list, 1), 0),
    'next_step', case when v_es_pagado then 'PUBLISH_WINNERS'
                      else coalesce(v_e.draw_fallback_policy, 'HOLD_FOR_REVIEW') end));
end $$;

-- ---------------------------------------------------------------------------
-- PUBLICAR GANADORES: un numero POR PREMIO cuando hay varios declarados.
-- Si hay un solo numero (RANDOM_SEEDED, EXTERNAL_LOTTERY o MANUAL simple),
-- se asigna a todos los premios (comportamiento anterior).
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
  v_prize   public.prizes;
  v_count   int := 0;
  v_numero  int;
  v_declared int[];
  v_sin_ganador text[] := array[]::text[];
  v_num     public.event_numbers;
  v_res     public.reservations;
begin
  select * into v_e from public.events e where e.id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El evento no existe.');
  end if;

  if not ((select private.is_owner())
          or private.has_merchant_permission(v_e.merchant_id, 'event.draw')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'No tenes permiso para publicar ganadores de este evento.');
  end if;

  if v_e.status <> 'CLOSED' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'El evento tiene que estar cerrado.',
      'details', jsonb_build_object('status', v_e.status));
  end if;

  select * into v_dr from public.draw_results dr where dr.event_id = p_event_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NO_DRAW_RESULT',
      'message', 'Primero registra el resultado del sorteo.');
  end if;

  -- Numeros declarados por puesto (MANUAL con varios premios).
  select coalesce(array_agg(t.value::int order by t.ord), '{}')
    into v_declared
    from jsonb_array_elements_text(coalesce(v_dr.raw_payload->'declared_numbers', '[]'::jsonb))
         with ordinality as t(value, ord);

  for v_prize in
    select * from public.prizes p
     where p.event_id = p_event_id and p.status = 'ACTIVE'
     order by p.position
  loop
    -- Un numero por puesto si hay varios declarados; sino el mismo para todos.
    if array_length(v_declared, 1) >= v_prize.position then
      v_numero := v_declared[v_prize.position];
    else
      v_numero := v_dr.computed_number;
    end if;

    select * into v_num from public.event_numbers en
     where en.event_id = p_event_id and en.number = v_numero;

    if v_num.status <> 'PAID' then
      v_sin_ganador := v_sin_ganador || v_prize.title;
      continue;
    end if;

    select * into v_res from public.reservations r where r.id = v_num.reservation_id;

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
      format('Ganaste el premio "%s"!', v_prize.title),
      format('Tu numero %s salio sorteado. Contacta al comercio para coordinar la entrega.', v_numero),
      v_e.merchant_id, p_event_id, v_res.id);
  end loop;

  if v_count = 0 then
    return jsonb_build_object('ok', false, 'code', 'NO_PRIZES',
      'message', 'El evento no tiene premios activos.');
  end if;

  -- Marca como WINNER solo el/los numeros que ganaron.
  if array_length(v_declared, 1) > 0 then
    update public.event_numbers en
       set status = 'WINNER', updated_at = now()
     where en.event_id = p_event_id
       and en.number = any(v_declared)
       and en.status = 'PAID';
  else
    update public.event_numbers en
       set status = 'WINNER', updated_at = now()
     where en.event_id = p_event_id and en.number = v_dr.computed_number;
  end if;

  update public.events e set status = 'DRAWN', updated_by = v_uid
   where e.id = p_event_id;

  perform private.log_audit('winner.published', 'event', p_event_id, v_e.merchant_id, p_event_id,
    jsonb_build_object('status', 'CLOSED'),
    jsonb_build_object('status', 'DRAWN', 'winners_created', v_count,
                       'draw_result_id', v_dr.id,
                       'prizes_without_winner', to_jsonb(v_sin_ganador)));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'event_id', p_event_id,
    'status', 'DRAWN',
    'winners_created', v_count,
    'prizes_without_winner', to_jsonb(v_sin_ganador)));
end $$;
