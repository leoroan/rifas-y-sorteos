-- =============================================================================
-- 0009_rls.sql
-- Row Level Security en TODAS las tablas + policies + vistas públicas.
-- La base de datos es la frontera de seguridad: React sólo decide qué mostrar.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) RLS en todas las tablas de public. Sin excepciones y sin "lo vemos después".
-- ---------------------------------------------------------------------------
do $$
declare
  t record;
begin
  for t in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
  loop
    execute format('alter table public.%I enable row level security', t.relname);
  end loop;
end $$;

-- Nota deliberada: NO se usa FORCE ROW LEVEL SECURITY. Los helpers son
-- security definer y necesitan poder leer las tablas sin RLS; con FORCE se
-- reactivaría RLS dentro de ellos y volvería la recursión infinita (42P17).
-- Y no aporta seguridad extra: los clientes no son dueños de las tablas.

-- ---------------------------------------------------------------------------
-- 2) Vistas públicas
-- security_invoker = true: la vista se evalúa con los permisos y las policies
-- del que consulta. Así la vista es una PROYECCIÓN (oculta columnas) y la
-- policy sigue siendo la que decide las filas. Doble barrera, no una sola.
-- ---------------------------------------------------------------------------
create or replace view public.public_merchants
with (security_invoker = true) as
select id, name, slug, description, logo_path,
       contact_phone, contact_whatsapp, contact_instagram,
       payment_instructions, timezone, currency
  from public.merchants
 where status = 'ACTIVE';

create or replace view public.public_events
with (security_invoker = true) as
select id, merchant_id, kind, title, slug, description, cover_path, status,
       starts_at, participation_ends_at, expected_draw_at, timezone,
       numbers_from, numbers_to, number_padding,
       price_per_number, currency,
       winner_method, winner_rule, draw_source_id, draw_shift,
       legal_status, terms_version_id,
       published_at, closed_at, drawn_at, cancelled_at, cancellation_reason
  from public.events;

-- Oculta reservation_id y el id interno de la fila: un participante puede ver
-- que el 25 está PAID, pero NO quién lo tiene.
create or replace view public.public_event_numbers
with (security_invoker = true) as
select event_id, number, display_code, status
  from public.event_numbers;

create or replace view public.public_prizes
with (security_invoker = true) as
select id, event_id, position, title, description, image_path,
       estimated_value, currency, conditions, status
  from public.prizes;

-- EXCEPCIÓN JUSTIFICADA: esta vista NO usa security_invoker, porque necesita
-- leer profiles para mostrar un nombre enmascarado ("Juan P."). Expone sólo el
-- nombre enmascarado: nunca el profile_id, el email ni el teléfono.
create or replace view public.public_event_winners
with (security_invoker = false) as
select w.event_id,
       w.prize_id,
       w.position,
       w.number,
       w.published_at,
       w.claim_status,
       nullif(
         split_part(coalesce(p.display_name, 'Participante'), ' ', 1)
         || case
              when coalesce(p.display_name, '') like '% %'
                then ' ' || left(split_part(p.display_name, ' ', 2), 1) || '.'
              else ''
            end,
         ''
       ) as winner_display
  from public.event_winners w
  join public.profiles p on p.id = w.profile_id
 where exists (
   select 1 from public.events e
    where e.id = w.event_id and e.status = 'DRAWN'
 );

comment on view public.public_event_winners is
  'Ganadores publicos con nombre enmascarado. Corre como dueño para poder leer profiles, pero solo proyecta el nombre enmascarado.';

grant select on public.public_merchants, public.public_events,
                public.public_event_numbers, public.public_prizes,
                public.public_event_winners
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) Policies
-- Convención: en las policies se escribe (select private.fn()) para que
-- Postgres la evalúe UNA vez como initplan en lugar de una vez por fila.
-- No hay policies de escritura para el negocio: toda escritura pasa por RPC.
-- ---------------------------------------------------------------------------

-- profiles -------------------------------------------------------------------
drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists profiles_select_owner on public.profiles;
create policy profiles_select_owner on public.profiles
  for select to authenticated
  using ((select private.is_owner()));

-- El comercio ve los datos de quienes participan en SUS eventos (y sólo ahí).
drop policy if exists profiles_select_merchant_scope on public.profiles;
create policy profiles_select_merchant_scope on public.profiles
  for select to authenticated
  using (exists (
    select 1 from public.reservations r
     where r.profile_id = profiles.id
       and private.is_event_staff(r.event_id)
  ));

-- Cada uno edita su propio perfil (nombre, teléfono). El rol de plataforma y
-- la suspensión están bloqueados por el trigger profiles_guard_privileges.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- merchants ------------------------------------------------------------------
drop policy if exists merchants_select_public on public.merchants;
create policy merchants_select_public on public.merchants
  for select to anon, authenticated
  using (status = 'ACTIVE');

drop policy if exists merchants_select_scope on public.merchants;
create policy merchants_select_scope on public.merchants
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(id));

-- merchant_members -----------------------------------------------------------
drop policy if exists merchant_members_select_self on public.merchant_members;
create policy merchant_members_select_self on public.merchant_members
  for select to authenticated
  using (profile_id = (select auth.uid()));

drop policy if exists merchant_members_select_scope on public.merchant_members;
create policy merchant_members_select_scope on public.merchant_members
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(merchant_id));

-- member_permissions ---------------------------------------------------------
drop policy if exists member_permissions_select on public.member_permissions;
create policy member_permissions_select on public.member_permissions
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (
      select 1 from public.merchant_members mm
       where mm.id = member_permissions.merchant_member_id
         and (mm.profile_id = (select auth.uid()) or private.is_merchant_of(mm.merchant_id))
    )
  );

-- Catálogo RBAC: lectura para todos, escritura sólo por migración/seed --------
drop policy if exists roles_select on public.roles;
create policy roles_select on public.roles for select to anon, authenticated using (true);

drop policy if exists permissions_select on public.permissions;
create policy permissions_select on public.permissions for select to anon, authenticated using (true);

drop policy if exists role_permissions_select on public.role_permissions;
create policy role_permissions_select on public.role_permissions
  for select to anon, authenticated using (true);

-- system_settings ------------------------------------------------------------
drop policy if exists system_settings_select_public on public.system_settings;
create policy system_settings_select_public on public.system_settings
  for select to anon, authenticated
  using (is_public = true);

drop policy if exists system_settings_select_owner on public.system_settings;
create policy system_settings_select_owner on public.system_settings
  for select to authenticated
  using ((select private.is_owner()));

-- merchant_settings ----------------------------------------------------------
drop policy if exists merchant_settings_select_scope on public.merchant_settings;
create policy merchant_settings_select_scope on public.merchant_settings
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(merchant_id));

-- events ---------------------------------------------------------------------
drop policy if exists events_select_public on public.events;
create policy events_select_public on public.events
  for select to anon, authenticated
  using (
    status in ('PUBLISHED','OPEN','CLOSED','DRAWN')
    and exists (
      select 1 from public.merchants m
       where m.id = events.merchant_id and m.status = 'ACTIVE'
    )
  );

drop policy if exists events_select_scope on public.events;
create policy events_select_scope on public.events
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(merchant_id));

-- event_numbers --------------------------------------------------------------
-- can_view_event cubre los dos casos: evento público, o staff del comercio.
-- NOTA: la columna reservation_id se protege con GRANT a nivel de columna
-- (0010_grants.sql), porque RLS no filtra columnas. Un participante puede ver
-- que el 25 está PAID, pero no quién lo tiene.
drop policy if exists event_numbers_select on public.event_numbers;
create policy event_numbers_select on public.event_numbers
  for select to anon, authenticated
  using (private.can_view_event(event_id));

-- prizes ---------------------------------------------------------------------
drop policy if exists prizes_select on public.prizes;
create policy prizes_select on public.prizes
  for select to anon, authenticated
  using (private.can_view_event(event_id));

-- draw_sources ---------------------------------------------------------------
drop policy if exists draw_sources_select on public.draw_sources;
create policy draw_sources_select on public.draw_sources
  for select to anon, authenticated
  using (is_active or (select private.is_owner()));

-- reservations ---------------------------------------------------------------
drop policy if exists reservations_select_own on public.reservations;
create policy reservations_select_own on public.reservations
  for select to authenticated
  using (profile_id = (select auth.uid()));

drop policy if exists reservations_select_scope on public.reservations;
create policy reservations_select_scope on public.reservations
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(merchant_id));

-- Sin policies de INSERT/UPDATE/DELETE: la reserva se crea y se mueve
-- exclusivamente por RPC (0011). Aunque alguien robe un JWT válido, no tiene
-- el verbo ni para insertar una reserva propia.

-- reservation_numbers (ledger) -----------------------------------------------
drop policy if exists reservation_numbers_select_own on public.reservation_numbers;
create policy reservation_numbers_select_own on public.reservation_numbers
  for select to authenticated
  using (exists (
    select 1 from public.reservations r
     where r.id = reservation_numbers.reservation_id
       and r.profile_id = (select auth.uid())
  ));

drop policy if exists reservation_numbers_select_scope on public.reservation_numbers;
create policy reservation_numbers_select_scope on public.reservation_numbers
  for select to authenticated
  using (exists (
    select 1 from public.reservations r
     where r.id = reservation_numbers.reservation_id
       and ((select private.is_owner()) or private.is_merchant_of(r.merchant_id))
  ));

-- payment_receipts -----------------------------------------------------------
drop policy if exists payment_receipts_select_own on public.payment_receipts;
create policy payment_receipts_select_own on public.payment_receipts
  for select to authenticated
  using (uploaded_by = (select auth.uid()));

-- El staff del comercio ve los comprobantes de SUS eventos, con el permiso de
-- revisión. Nunca los de otro comercio, ni siquiera conociendo el UUID.
drop policy if exists payment_receipts_select_scope on public.payment_receipts;
create policy payment_receipts_select_scope on public.payment_receipts
  for select to authenticated
  using ((select private.is_owner())
         or private.has_merchant_permission(merchant_id, 'payment.receipt.review'));

-- El participante puede subir la METADATA, nunca revisarla ni modificarla.
drop policy if exists payment_receipts_insert_own on public.payment_receipts;
create policy payment_receipts_insert_own on public.payment_receipts
  for insert to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and status = 'PENDING'
    and reviewed_by is null
    and reviewed_at is null
    and exists (
      select 1 from public.reservations r
       where r.id = reservation_id
         and r.profile_id = (select auth.uid())
         and r.event_id = payment_receipts.event_id
         and r.merchant_id = payment_receipts.merchant_id
         and r.status in ('PENDING','PAYMENT_SUBMITTED')
    )
  );

-- NO existe policy de UPDATE: es imposible que un participante apruebe su
-- propio comprobante. La aprobación sólo ocurre en review_receipt (0011).

-- draw_results ---------------------------------------------------------------
-- Público: sólo cuando el evento ya fue sorteado. El resultado es un hecho
-- público, con su seed, para que cualquiera pueda verificarlo.
drop policy if exists draw_results_select_public on public.draw_results;
create policy draw_results_select_public on public.draw_results
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.events e
       where e.id = draw_results.event_id and e.status = 'DRAWN'
    )
    and private.can_view_event(event_id)
  );

drop policy if exists draw_results_select_scope on public.draw_results;
create policy draw_results_select_scope on public.draw_results
  for select to authenticated
  using (
    (select private.is_owner())
    or exists (
      select 1 from public.events e
       where e.id = draw_results.event_id
         and private.is_merchant_of(e.merchant_id)
    )
  );

-- event_winners --------------------------------------------------------------
drop policy if exists event_winners_select_public on public.event_winners;
create policy event_winners_select_public on public.event_winners
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.events e
       where e.id = event_winners.event_id and e.status = 'DRAWN'
    )
    and private.can_view_event(event_id)
  );

drop policy if exists event_winners_select_scope on public.event_winners;
create policy event_winners_select_scope on public.event_winners
  for select to authenticated
  using (
    (select private.is_owner())
    or private.is_merchant_of((select e.merchant_id from public.events e where e.id = event_winners.event_id))
  );

-- notifications --------------------------------------------------------------
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (recipient_profile_id = (select auth.uid()));

drop policy if exists notifications_select_owner on public.notifications;
create policy notifications_select_owner on public.notifications
  for select to authenticated
  using ((select private.is_owner()));

-- Sólo se puede marcar como leída. Las columnas escribibles se limitan con
-- GRANT a nivel de columna en 0010_grants.sql (read_at, status).
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (recipient_profile_id = (select auth.uid()))
  with check (recipient_profile_id = (select auth.uid()));

-- terms_versions -------------------------------------------------------------
-- Lectura abierta: hay que poder leerlas ANTES de aceptarlas.
drop policy if exists terms_versions_select on public.terms_versions;
create policy terms_versions_select on public.terms_versions
  for select to anon, authenticated using (true);

-- terms_acceptances ----------------------------------------------------------
drop policy if exists terms_acceptances_select_own on public.terms_acceptances;
create policy terms_acceptances_select_own on public.terms_acceptances
  for select to authenticated
  using (profile_id = (select auth.uid()));

drop policy if exists terms_acceptances_select_scope on public.terms_acceptances;
create policy terms_acceptances_select_scope on public.terms_acceptances
  for select to authenticated
  using (
    (select private.is_owner())
    or (event_id is not null and private.is_event_staff(event_id))
  );

drop policy if exists terms_acceptances_insert_own on public.terms_acceptances;
create policy terms_acceptances_insert_own on public.terms_acceptances
  for insert to authenticated
  with check (profile_id = (select auth.uid()));

-- El hash declarado tiene que ser el de la versión real: no se puede "aceptar"
-- un texto que no existe, ni inventar qué versión se aceptó.
create or replace function private.guard_acceptance_hash()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_hash text;
begin
  select tv.content_hash into v_hash
    from public.terms_versions tv
   where tv.id = new.terms_version_id;

  if v_hash is null then
    raise exception 'UNKNOWN_TERMS_VERSION' using errcode = '23503';
  end if;

  if new.content_hash_snapshot is distinct from v_hash then
    raise exception 'TERMS_HASH_MISMATCH'
      using errcode = '23514',
            detail  = 'El hash de aceptacion no corresponde a la version declarada.';
  end if;

  return new;
end $$;

drop trigger if exists terms_acceptances_guard_hash on public.terms_acceptances;
create trigger terms_acceptances_guard_hash
  before insert on public.terms_acceptances
  for each row execute function private.guard_acceptance_hash();

-- audit_logs -----------------------------------------------------------------
drop policy if exists audit_logs_select_own on public.audit_logs;
create policy audit_logs_select_own on public.audit_logs
  for select to authenticated
  using (actor_profile_id = (select auth.uid()));

drop policy if exists audit_logs_select_scope on public.audit_logs;
create policy audit_logs_select_scope on public.audit_logs
  for select to authenticated
  using (
    (select private.is_owner())
    or (merchant_id is not null and private.is_merchant_of(merchant_id))
  );

-- Sin INSERT para nadie: los logs se escriben SÓLO desde private.log_audit(),
-- que es security definer y por lo tanto no pasa por RLS.

-- security_blocks ------------------------------------------------------------
drop policy if exists security_blocks_select_scope on public.security_blocks;
create policy security_blocks_select_scope on public.security_blocks
  for select to authenticated
  using ((select private.is_owner()) or private.is_merchant_of(merchant_id));

-- Sin escritura directa: bloquear y desbloquear pasa por RPC auditada.

-- ---------------------------------------------------------------------------
-- 4) Verificación: no debe quedar ninguna tabla de public sin RLS.
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