-- =============================================================================
-- 0023_short_application_form.sql
-- El formulario público de contacto es CORTO (nombre, apellido, y un contacto
-- — email o teléfono — + mensaje). Los datos completos del negocio se piden
-- en el onboarding, después de que el OWNER aprueba/invita.
-- =============================================================================

create or replace function public.application_submit(
  p_nombre    text,
  p_apellido  text,
  p_email     text,
  p_negocio   text,
  p_dni       text,
  p_tax_type  text,
  p_tax_id    text,
  p_telefono  text,
  p_message   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_tel   text := btrim(coalesce(p_telefono, ''));
  v_id    uuid;
begin
  if p_nombre is null or char_length(btrim(p_nombre)) < 2 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'message', 'Falta tu nombre.');
  end if;
  if p_apellido is null or char_length(btrim(p_apellido)) < 2 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'message', 'Falta tu apellido.');
  end if;

  -- Al menos UN contacto: email válido O teléfono.
  if (v_email = '' or v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
     and char_length(v_tel) < 6 then
    return jsonb_build_object('ok', false, 'code', 'CONTACT_REQUIRED',
      'message', 'Dejanos al menos un email o un teléfono para contactarte.');
  end if;
  if v_email <> '' and v_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_EMAIL', 'message', 'El email no parece válido.');
  end if;

  -- ¿Ya es organizador activo con ese email?
  if v_email <> '' and exists (
    select 1 from public.profiles p
      join public.merchant_members mm on mm.profile_id = p.id and mm.status = 'ACTIVE'
     where lower(p.email) = v_email
  ) then
    return jsonb_build_object('ok', false, 'code', 'ALREADY_MERCHANT',
      'message', 'Ese email ya publica sorteos. Iniciá sesión.');
  end if;

  insert into public.merchant_applications (
    nombre, apellido, email, negocio, dni, tax_type, tax_id, telefono, message, status
  ) values (
    btrim(p_nombre), btrim(p_apellido), nullif(v_email, ''),
    nullif(btrim(coalesce(p_negocio,'')), ''),
    nullif(btrim(coalesce(p_dni,'')), ''),
    nullif(p_tax_type,''), nullif(btrim(coalesce(p_tax_id,'')), ''),
    nullif(v_tel, ''), nullif(btrim(coalesce(p_message,'')), ''),
    'PENDING'
  )
  on conflict ((lower(email))) do update
     set nombre = excluded.nombre, apellido = excluded.apellido, negocio = excluded.negocio,
         dni = excluded.dni, tax_type = excluded.tax_type, tax_id = excluded.tax_id,
         telefono = excluded.telefono, message = excluded.message, status = 'PENDING'
  returning id into v_id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'application_id', v_id,
    'message', 'Recibimos tu mensaje. Te vamos a contactar.'));
end $$;