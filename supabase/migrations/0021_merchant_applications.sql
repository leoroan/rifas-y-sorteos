-- =============================================================================
-- 0021_merchant_applications.sql
-- Flujo de tenants: formulario público → revisión del OWNER → onboarding
-- obligatorio del comerciante (datos + plan + ToS) → queda como comerciante.
-- =============================================================================

create table if not exists public.merchant_applications (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  apellido    text not null,
  email       text not null,
  negocio     text not null,
  dni         text,
  tax_type    text check (tax_type in ('CUIT','CUIL')),
  tax_id      text,
  telefono    text not null,
  message     text,
  status      text not null default 'PENDING',
  plan_code   text not null default 'FREE' references public.plans(code) on delete restrict,
  review_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  profile_id  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint merchant_applications_status_valid
    check (status in ('PENDING','APPROVED','REJECTED','COMPLETED'))
);

comment on table public.merchant_applications is
  'Solicitudes para ser comerciante. Contacto publico (sin exponer el email del OWNER) -> revision del OWNER -> onboarding obligatorio -> comerciante.';

alter table public.merchant_applications enable row level security;

-- El OWNER ve y revisa todo; el solicitante ve su propia solicitud (por email).
drop policy if exists merchant_applications_select_scope on public.merchant_applications;
create policy merchant_applications_select_scope on public.merchant_applications
  for select to authenticated
  using ((select private.is_owner()) or lower(email) = lower((select email from public.profiles where id = (select auth.uid()))));

revoke all on public.merchant_applications from anon, authenticated;
grant select on public.merchant_applications to authenticated;

create index if not exists merchant_applications_status_idx on public.merchant_applications (status, created_at desc);
create unique index if not exists merchant_applications_email_uk on public.merchant_applications (lower(email));

drop trigger if exists merchant_applications_set_updated_at on public.merchant_applications;
create trigger merchant_applications_set_updated_at
  before update on public.merchant_applications
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- REVISAR SOLICITUD (OWNER). Aprueba (asignando plan) o rechaza (con nota).
-- ---------------------------------------------------------------------------
create or replace function public.application_review(
  p_application_id uuid,
  p_decision      text,
  p_plan_code    text default 'FREE',
  p_note         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a public.merchant_applications;
begin
  if not (select private.is_owner()) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Solo el propietario de la plataforma revisa solicitudes.');
  end if;

  if p_decision not in ('APPROVE','REJECT') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_DECISION', 'message', 'Decision invalida.');
  end if;

  select * into v_a from public.merchant_applications a where a.id = p_application_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'La solicitud no existe.');
  end if;

  if v_a.status <> 'PENDING' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', 'La solicitud ya fue revisada.');
  end if;

  if p_decision = 'REJECT' and (p_note is null or char_length(btrim(p_note)) < 5) then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED',
      'message', 'Indica el motivo del rechazo (minimo 5 caracteres).');
  end if;

  update public.merchant_applications a
     set status = case when p_decision = 'APPROVE' then 'APPROVED' else 'REJECTED' end,
         plan_code = case when p_decision = 'APPROVE' then coalesce(p_plan_code, 'FREE') else a.plan_code end,
         review_note = nullif(btrim(coalesce(p_note, '')), ''),
         reviewed_by = (select auth.uid()),
         reviewed_at = now()
   where a.id = p_application_id;

  perform private.log_audit(
    case when p_decision = 'APPROVE' then 'application.approved' else 'application.rejected' end,
    'merchant_application', p_application_id, null, null,
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', case when p_decision = 'APPROVE' then 'APPROVED' else 'REJECTED' end,
                       'plan', coalesce(p_plan_code, 'FREE'), 'note', p_note));

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'application_id', p_application_id,
    'status', case when p_decision = 'APPROVE' then 'APPROVED' else 'REJECTED' end));
end $$;

-- ---------------------------------------------------------------------------
-- COMPLETAR ONBOARDING (el solicitante). Crea el comercio + lo hace
-- comerciante. Exige: sesion con el email de la solicitud, solicitud
-- APROVED, ToS aceptados, y todos los datos del negocio.
-- ---------------------------------------------------------------------------
create or replace function public.application_complete(
  p_application_id      uuid,
  p_merchant_name        text,
  p_merchant_slug        text,
  p_tax_type             text,
  p_tax_id               text,
  p_contact_phone        text,
  p_terms_version_id     uuid,
  p_contact_whatsapp     text default null,
  p_contact_instagram    text default null,
  p_payment_instructions text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_a  public.merchant_applications;
  v_mid uuid;
  v_slug text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', 'Necesitas una sesion.');
  end if;

  select * into v_a from public.merchant_applications a where a.id = p_application_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'La solicitud no existe.');
  end if;

  -- La sesion tiene que ser del email de la solicitud.
  if lower(v_a.email) <> lower(coalesce((select email from public.profiles where id = v_uid), '')) then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN',
      'message', 'Esta solicitud no corresponde a tu email.');
  end if;

  if v_a.status <> 'APPROVED' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'message', case v_a.status
                   when 'COMPLETED' then 'Ya completaste el alta de tu comercio.'
                   when 'PENDING' then 'Tu solicitud todavia no fue aprobada.'
                   when 'REJECTED' then 'Tu solicitud fue rechazada.'
                   else 'La solicitud no esta aprobada.'
                 end);
  end if;

  if p_merchant_name is null or char_length(btrim(p_merchant_name)) < 2 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'message', 'Falta el nombre del comercio.');
  end if;
  if p_tax_type is null or p_tax_type not in ('CUIT','CUIL') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'message', 'Elegi CUIT o CUIL.');
  end if;
  if p_tax_id is null or char_length(btrim(p_tax_id)) < 6 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'message', 'Falta la clave fiscal (CUIT/CUIL).');
  end if;
  if p_contact_phone is null or char_length(btrim(p_contact_phone)) < 6 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'message', 'Falta el telefono del comercio.');
  end if;

  -- ToS: tienen que estar aceptados por esta persona y version.
  if not exists (
    select 1 from public.terms_acceptances ta
     where ta.profile_id = v_uid and ta.terms_version_id = p_terms_version_id
  ) then
    return jsonb_build_object('ok', false, 'code', 'TERMS_NOT_ACCEPTED',
      'message', 'Tenos que aceptar los terminos y condiciones para continuar.');
  end if;

  v_slug := lower(btrim(coalesce(p_merchant_slug, '')));
  if v_slug = '' then
    v_slug := lower(regexp_replace(btrim(p_merchant_name), '[^a-z0-9]+', '-', 'gi'));
    v_slug := regexp_replace(v_slug, '^-+|-+$', '');
  end if;
  if v_slug !~ '^[a-z0-9]([a-z0-9-]{1,38})[a-z0-9]$' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_SLUG',
      'message', 'El identificador tiene que ser minusculas, numeros y guiones (3-40).');
  end if;

  if exists (select 1 from public.merchants m where lower(m.slug) = v_slug) then
    return jsonb_build_object('ok', false, 'code', 'SLUG_TAKEN',
      'message', 'Ya existe un comercio con ese identificador. Elegi otro.');
  end if;

  -- Crear el comercio con el plan otorgado en la revision.
  insert into public.merchants (name, slug, tax_type, tax_id, contact_phone, contact_whatsapp,
                                contact_instagram, payment_instructions, plan_code, created_by)
  values (btrim(p_merchant_name), v_slug, p_tax_type, btrim(p_tax_id), btrim(p_contact_phone),
          nullif(btrim(coalesce(p_contact_whatsapp, '')), ''),
          nullif(btrim(coalesce(p_contact_instagram, '')), ''),
          nullif(btrim(coalesce(p_payment_instructions, '')), ''),
          v_a.plan_code, (select auth.uid()))
  returning id into v_mid;

  -- El solicitante queda como COMERCIANTE de su comercio (alta auditada).
  insert into public.merchant_members (merchant_id, profile_id, role, status, invited_by)
  values (v_mid, v_uid, 'MERCHANT', 'ACTIVE', (select auth.uid()))
  on conflict (merchant_id, profile_id) do update
     set role = 'MERCHANT', status = 'ACTIVE', suspended_at = null, removed_at = null;

  update public.merchant_applications a
     set status = 'COMPLETED', profile_id = v_uid, updated_at = now()
   where a.id = p_application_id;

  perform private.log_audit('application.completed', 'merchant_application', p_application_id, v_mid, null,
    jsonb_build_object('status', 'APPROVED'),
    jsonb_build_object('status', 'COMPLETED', 'merchant_id', v_mid, 'plan', v_a.plan_code));

  perform private.log_audit('role.assign_merchant', 'merchant_member', v_uid, v_mid, null,
    null,
    jsonb_build_object('role', 'MERCHANT', 'status', 'ACTIVE', 'plan', v_a.plan_code),
    jsonb_build_object('assigned_to', v_uid, 'via', 'application'));

  perform private.fn_notify(v_uid, 'staff.added', 'Tu comercio esta listo',
    'Ya podes entrar al panel y crear tu primer sorteo.', v_mid, null, null);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'merchant_id', v_mid, 'plan', v_a.plan_code,
    'redirect', '/panel'));
end $$;

revoke all on function public.application_review(uuid, text, text, text) from public, anon;
revoke all on function public.application_complete(uuid, text, text, text, text, text, uuid, text, text, text) from public, anon;
grant execute on function public.application_review(uuid, text, text, text) to authenticated;
grant execute on function public.application_complete(uuid, text, text, text, text, text, uuid, text, text, text) to authenticated;
