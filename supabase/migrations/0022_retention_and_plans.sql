-- =============================================================================
-- 0022_retention_and_plans.sql
-- Retención de históricos según el plan + gestión de planes por el OWNER.
-- =============================================================================

-- ¿Qué eventos son elegibles para borrado por retención?
-- Criterio: CLOSED/DRAWN + now() > closed_at + retention_days (del plan)
-- Y nunca antes del último reclamo de premios.
create or replace function private.fn_events_eligible_for_retention()
returns table (event_id uuid, merchant_id uuid, closed_at timestamptz, retention_days int, delete_after timestamptz)
language sql stable security definer set search_path = ''
as $$
  select e.id, e.merchant_id, e.closed_at, p.retention_days,
         greatest(e.closed_at + make_interval(days => p.retention_days),
                  coalesce((select max(w.claim_deadline_at) from public.event_winners w where w.event_id = e.id), e.closed_at))
    from public.events e
    join public.merchants m on m.id = e.merchant_id
    join public.plans p on p.code = m.plan_code
   where p.retention_days is not null
     and e.status in ('CLOSED','DRAWN')
     and e.closed_at is not null
     and now() > greatest(
         e.closed_at + make_interval(days => p.retention_days),
         coalesce((select max(w.claim_deadline_at) from public.event_winners w where w.event_id = e.id), e.closed_at))
$$;

-- Borrar un evento por retención. Se preserva auditoría (se desvincula).
create or replace function private.fn_retention_delete_event(p_event_id uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  update public.audit_logs set event_id = null where event_id = p_event_id;
  update public.notifications set event_id = null where event_id = p_event_id;
  delete from public.event_winners where event_id = p_event_id;
  delete from public.draw_results where event_id = p_event_id;
  delete from public.payment_receipts where event_id = p_event_id;
  delete from public.reservation_numbers where event_id = p_event_id;
  delete from public.reservations where event_id = p_event_id;
  delete from public.event_numbers where event_id = p_event_id;
  delete from public.prizes where event_id = p_event_id;
  delete from public.events where id = p_event_id;
  return true;
end $$;

-- Job: borra todos los elegibles. Lo corre pg_cron diariamente.
create or replace function public.run_retention_purge(p_limit int default 20)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_count int := 0;
  r record;
begin
  for r in
    select event_id from private.fn_events_eligible_for_retention()
    order by closed_at asc limit greatest(p_limit, 1)
  loop
    perform private.fn_retention_delete_event(r.event_id);
    v_count := v_count + 1;
    perform private.log_audit('event.retention_deleted', 'event', r.event_id, null, null,
      null, jsonb_build_object('action', 'retention_purge'));
  end loop;
  return v_count;
end $$;

revoke all on function public.run_retention_purge(int) from public, anon, authenticated;
grant execute on function public.run_retention_purge(int) to service_role;

-- RPC: el OWNER cambia el plan de un comercio.
create or replace function public.admin_set_merchant_plan(
  p_merchant_id uuid,
  p_plan_code   text
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Solo el propietario de la plataforma cambia planes.');
  end if;
  if not exists (select 1 from public.plans where code = p_plan_code and is_active) then
    return jsonb_build_object('ok', false, 'code', 'INVALID_PLAN', 'message', 'Ese plan no existe.');
  end if;
  if not exists (select 1 from public.merchants where id = p_merchant_id) then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'El comercio no existe.');
  end if;

  update public.merchants set plan_code = p_plan_code where id = p_merchant_id;
  perform private.log_audit('merchant.plan_changed', 'merchant', p_merchant_id, p_merchant_id, null,
    null, jsonb_build_object('plan', p_plan_code));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'merchant_id', p_merchant_id, 'plan', p_plan_code));
end $$;

revoke all on function public.admin_set_merchant_plan(uuid, text) from public, anon;
grant execute on function public.admin_set_merchant_plan(uuid, text) to authenticated;

-- Programar el job con pg_cron.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron no disponible. Corre run_retention_purge manualmente.';
    return;
  end if;
  if exists (select 1 from cron.job where jobname = 'riffles-retention-purge') then
    perform cron.unschedule('riffles-retention-purge');
  end if;
  perform cron.schedule('riffles-retention-purge', '0 3 * * *', 'select public.run_retention_purge(20)');
  raise notice 'Job de retencion programado (diario 03:00).';
exception when others then
  raise notice 'No se pudo programar: %', sqlerrm;
end $$;