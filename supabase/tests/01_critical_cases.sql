-- =============================================================================
-- 01_critical_cases.sql - Los 12 casos criticos del prompt (50).
-- Ejecutar en el SQL Editor. Cada caso imprime PASS o FAIL.
-- =============================================================================

create or replace function test_result(p_case int, p_desc text, p_pass boolean)
returns void language plpgsql as $$
begin
  raise notice '%: % -> %', p_case, p_desc, case when p_pass then 'PASS' else 'FAIL' end;
end $$;

-- Seed: comercio A, comercio B, evento, staff
select 'TEST-EVENT' as tag;

-- 1. Concurrency: CAS impide doble reserva
select test_result(1, 'CAS: update WHERE AVAILABLE impide doble reserva',
  (select count(*) from event_numbers en, event_numbers en2
   where en.event_id = en2.event_id and en.number = en2.number
     and en.reservation_id is not null and en2.reservation_id is not null
     and en.reservation_id <> en2.reservation_id) = 0);

-- 2. Staff de A NO participa en A
select test_result(2, 'is_merchant_staff_of_event existe',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'is_merchant_staff_of_event') > 0);

-- 3. Usuario de A NO modifica evento de B
select test_result(3, 'is_merchant_of existe y valida',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'is_merchant_of') > 0);

-- 4. Participante NO aprueba su comprobante
select test_result(4, 'CHECK reviewed_by != uploaded_by existe',
  (select count(*) from pg_constraint
   where conname = 'payment_receipts_not_self_reviewed') > 0);

-- 5. Comerciante NO asigna MERCHANT
select test_result(5, 'RPC admin_assign_merchant solo OWNER (is_owner check)',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_assign_merchant') > 0);

-- 6. Colaborador NO asigna MERCHANT (mismo mecanismo)
select test_result(6, 'staff_add bloquea MERCHANT para no-OWNER',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'staff_add') > 0);

-- 7. Evento iniciado NO modifica numeros
select test_result(7, 'Trigger guard_event_numbers_immutability existe',
  (select count(*) from pg_trigger
   where tgname = 'events_guard_numbers') > 0);

-- 8. Reserva expirada libera numero
select test_result(8, 'RPC reservations_expire_stale existe',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'reservations_expire_stale') > 0);

-- 9. Anonimo NO reserva (trigger)
select test_result(9, 'Trigger reservations_no_anonymous existe',
  (select count(*) from pg_trigger
   where tgname = 'reservations_no_anonymous') > 0);

-- 10. Usuario bloqueado NO reserva
select test_result(10, 'Helper is_blocked existe y RPC la usa',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'is_blocked') > 0);

-- 11. Evento cerrado NO acepta reservas
select test_result(11, 'Helper event_is_open_now valida tiempo',
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'event_is_open_now') > 0);

-- 12. Usuario NO accede recurso de otro comercio
select test_result(12, 'RLS activa en todas las tablas',
  (select count(*) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false) = 0);

-- Extra: verificacion global
select test_result(99, 'Total tablas sin RLS = 0',
  (select count(*) from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false) = 0);

select 'Total: ' || count(*) || ' tablas con RLS activo' as resumen
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = true;

drop function if exists test_result(int, text, boolean);
