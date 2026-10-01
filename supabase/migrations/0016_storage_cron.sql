-- =============================================================================
-- 0016_storage_cron.sql
-- Buckets, policies de Storage y trabajos programados (pg_cron).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Buckets
-- receipts: PRIVADO. Los comprobantes pueden tener datos bancarios y nombres.
-- public-assets: público (logos e imágenes de premios).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 8388608,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update
   set public = false,
       file_size_limit = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('public-assets', 'public-assets', true, 5242880,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
   set public = true,
       file_size_limit = excluded.file_size_limit,
       allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Policies de storage.objects
-- Path de receipts: {merchant_id}/{event_id}/{reservation_id}/{uuid}.{ext}
-- OJO: storage.foldername(name) devuelve text[] 1-BASED y SIN el filename.
-- ---------------------------------------------------------------------------

-- El dueño de la reserva sube su comprobante, sólo dentro de su carpeta.
drop policy if exists receipts_insert_own on storage.objects;
create policy receipts_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and exists (
      select 1 from public.reservations r
       where r.id = ((storage.foldername(name))[3])::uuid
         and r.profile_id = (select auth.uid())
         and r.status in ('PENDING','PAYMENT_SUBMITTED')
    )
  );

-- Lo ve el dueño, o el staff del comercio dueño de la carpeta (con permiso de
-- revisión). El merchant_id sale del PATH, no de un parámetro del cliente:
-- un colaborador del comercio B no puede leer comprobantes del A ni tocando el path.
drop policy if exists receipts_select_scoped on storage.objects;
create policy receipts_select_scoped on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and (
      exists (
        select 1 from public.reservations r
         where r.id = ((storage.foldername(name))[3])::uuid
           and r.profile_id = (select auth.uid())
      )
      or private.has_merchant_permission(
           ((storage.foldername(name))[1])::uuid, 'payment.receipt.review')
    )
  );

-- NO hay policies de UPDATE ni DELETE para receipts: un comprobante subido no
-- se reemplaza. Para corregir se sube otro (uno PENDING por reserva).

-- public-assets: lectura pública (bucket público), escritura sólo del staff
-- dentro de la carpeta de SU comercio.
drop policy if exists public_assets_select on storage.objects;
create policy public_assets_select on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'public-assets');

drop policy if exists public_assets_insert_staff on storage.objects;
create policy public_assets_insert_staff on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'public-assets'
    and private.is_merchant_of(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists public_assets_delete_staff on storage.objects;
create policy public_assets_delete_staff on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'public-assets'
    and private.is_merchant_of(((storage.foldername(name))[1])::uuid)
  );

-- ---------------------------------------------------------------------------
-- Sincronización de estado por tiempo.
-- El estado DESCRIBE, pero la autoridad es el reloj (§6.1). Este job sólo
-- mantiene el panel ordenado; las RPC validan el tiempo igual.
-- ---------------------------------------------------------------------------
create or replace function private.fn_sync_event_status()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_open int := 0;
begin
  -- PUBLISHED -> OPEN cuando empezó la ventana.
  update public.events e
     set status = 'OPEN'
   where e.status = 'PUBLISHED'
     and now() >= e.starts_at
     and now() <= e.participation_ends_at;
  get diagnostics v_open = row_count;

  -- OPEN -> CLOSED cuando terminó la ventana.
  update public.events e
     set status = 'CLOSED', closed_at = coalesce(e.closed_at, now())
   where e.status = 'OPEN'
     and now() > e.participation_ends_at;

  return v_open;
end $$;

-- Cierra las reservas cuya revisión se venció SIN castigar al participante:
-- vuelven a PENDING con un plazo nuevo, y se avisa al comercio. Si no, el que
-- hizo todo bien perdería los números porque el comercio no revisó.
create or replace function private.fn_escalate_overdue_reviews()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_n   int;
  v_id  uuid;
begin
  select array_agg(x.id) into v_ids
    from (
      select r.id from public.reservations r
       where r.status = 'PAYMENT_SUBMITTED'
         and r.review_deadline_at is not null
         and r.review_deadline_at < now()
       limit 200
       for update skip locked
    ) x;

  if v_ids is null then return 0; end if;

  update public.reservations r
     set status = 'PENDING',
         review_deadline_at = null,
         expires_at = now() + coalesce(
           (select case when p.is_anonymous then e.reservation_ttl_anonymous
                        else e.reservation_ttl_registered end
              from public.events e join public.profiles p on p.id = r.profile_id
             where e.id = r.event_id),
           interval '12 hours'),
         review_note = coalesce(r.review_note, '') || ' [revision vencida: plazo renovado]'
   where r.id = any(v_ids);

  get diagnostics v_n = row_count;

  foreach v_id in array v_ids loop
    perform private.log_audit('receipt.review_overdue', 'reservation', v_id,
      (select merchant_id from public.reservations where id = v_id),
      (select event_id from public.reservations where id = v_id),
      jsonb_build_object('status', 'PAYMENT_SUBMITTED'),
      jsonb_build_object('status', 'PENDING', 'reason', 'REVIEW_DEADLINE_EXCEEDED'));

    perform private.fn_notify(
      (select profile_id from public.reservations where id = v_id),
      'payment.correction_requested',
      'Seguimos revisando tu pago',
      'Tu reserva sigue vigente: renovamos el plazo mientras el comercio revisa el comprobante.',
      (select merchant_id from public.reservations where id = v_id),
      (select event_id from public.reservations where id = v_id),
      v_id);
  end loop;

  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- Retención de usuarios anónimos: REPORTE, no borrado automático.
-- Borrar usuarios de auth.users es irreversible; el OWNER decide cuándo.
-- ---------------------------------------------------------------------------
create or replace function public.admin_anonymous_retention_report(p_days int default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days int;
  v_candidates int;
  v_total_anon int;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Sólo el administrador de la plataforma puede ver este reporte.');
  end if;

  v_days := coalesce(
    p_days,
    nullif(private.fn_effective_setting(null, 'security.retention.anonymous_days') #>> '{}','')::int,
    90
  );

  select count(*) into v_total_anon
    from public.profiles p where p.is_anonymous = true and p.status = 'ACTIVE';

  select count(*) into v_candidates
    from public.profiles p
   where p.is_anonymous = true
     and p.status = 'ACTIVE'
     and coalesce(p.last_seen_at, p.created_at) < now() - make_interval(days => v_days)
     and not exists (
       select 1 from public.event_winners w where w.profile_id = p.id
     )
     and not exists (
       select 1 from public.reservations r
        where r.profile_id = p.id
          and r.status in ('PENDING','PAYMENT_SUBMITTED','APPROVED')
     );

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'days', v_days,
    'total_anonymous', v_total_anon,
    'purge_candidates', v_candidates));
end $$;

revoke all on function public.admin_anonymous_retention_report(int) from public, anon;
grant execute on function public.admin_anonymous_retention_report(int) to authenticated;

-- ---------------------------------------------------------------------------
-- pg_cron
-- Si la extensión no está habilitada, se avisa y se puede activar desde
-- Dashboard → Integrations → Cron. Nada de esto es crítico: las RPC validan
-- el tiempo y liberan holds vencidos de forma defensiva.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron no esta instalado. Habilitalo en Dashboard -> Database -> Extensions y volve a ejecutar este bloque. Las RPC siguen funcionando (validan el tiempo y liberan holds vencidos por si mismas).';
    return;
  end if;

  -- Reservas vencidas: cada minuto.
  if exists (select 1 from cron.job where jobname = 'riffles-expire-reservations') then
    perform cron.unschedule('riffles-expire-reservations');
  end if;
  perform cron.schedule('riffles-expire-reservations', '* * * * *',
                        'select public.reservations_expire_stale(500)');

  -- Estados por tiempo: cada 5 minutos.
  if exists (select 1 from cron.job where jobname = 'riffles-sync-event-status') then
    perform cron.unschedule('riffles-sync-event-status');
  end if;
  perform cron.schedule('riffles-sync-event-status', '*/5 * * * *',
                        'select private.fn_sync_event_status()');

  -- Revisiones vencidas: cada 15 minutos (no castiga al participante).
  if exists (select 1 from cron.job where jobname = 'riffles-overdue-reviews') then
    perform cron.unschedule('riffles-overdue-reviews');
  end if;
  perform cron.schedule('riffles-overdue-reviews', '*/15 * * * *',
                        'select private.fn_escalate_overdue_reviews()');

  -- Purgas de retención: daily. Borra hashes de bloqueos vencidos y nada más.
  if exists (select 1 from cron.job where jobname = 'riffles-retention') then
    perform cron.unschedule('riffles-retention');
  end if;
  perform cron.schedule('riffles-retention', '30 4 * * *', $job$
    delete from public.security_blocks sb
     where sb.subject_key is not null
       and sb.lifted_at is null
       and sb.blocked_until is not null
       and sb.blocked_until < now() - interval '30 days';
  $job$);

  raise notice 'pg_cron: 4 trabajos programados.';
exception when others then
  raise notice 'No se pudieron programar los trabajos de pg_cron: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Verificación final
-- ---------------------------------------------------------------------------
do $$
declare
  v_tablas int;
  v_policies int;
  v_sin_rls int;
  v_rpc int;
begin
  select count(*) into v_tablas from information_schema.tables
   where table_schema = 'public' and table_type = 'BASE TABLE';
  select count(*) into v_policies from pg_policies where schemaname = 'public';
  select count(*) into v_sin_rls from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false;
  select count(*) into v_rpc from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public';

  raise notice 'RESUMEN: % tablas, % policies, % tablas sin RLS, % funciones en public.',
    v_tablas, v_policies, v_sin_rls, v_rpc;

  if v_sin_rls > 0 then
    raise exception 'HAY TABLAS SIN RLS: revisar antes de usar la plataforma.';
  end if;
end $$;