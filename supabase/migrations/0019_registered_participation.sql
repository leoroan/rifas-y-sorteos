-- =============================================================================
-- 0019_registered_participation.sql
-- Q1 (confirmado por el OWNER): los usuarios ANÓNIMOS pueden VER eventos
-- públicos, números y disponibilidad, pero NO pueden RESERVAR. Para reservar
-- hay que registrarse (email). Se hace cumplir en la base, no sólo en React.
-- =============================================================================

-- Un usuario anónimo no puede insertar una reserva. Este trigger se dispara
-- también cuando la inserción la hace la RPC reservation_create (que es
-- security definer), así que no hay forma de saltearlo desde el cliente.
create or replace function private.guard_no_anonymous_reservation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.profiles p
     where p.id = new.profile_id
       and p.is_anonymous = true
  ) then
    raise exception 'REGISTRATION_REQUIRED'
      using errcode = '42501',
            detail = 'Para reservar números hay que registrarse (email). Los usuarios anónimos pueden ver los eventos, pero no reservar.';
  end if;
  return new;
end $$;

comment on function private.guard_no_anonymous_reservation() is
  'Participación registrada: ver público sin cuenta, reservar requiere registro (Q1).';

drop trigger if exists reservations_no_anonymous on public.reservations;
create trigger reservations_no_anonymous
  before insert on public.reservations
  for each row execute function private.guard_no_anonymous_reservation();