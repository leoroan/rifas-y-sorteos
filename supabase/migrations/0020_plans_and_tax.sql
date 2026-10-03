-- =============================================================================
-- 0020_plans_and_tax.sql
-- Planes de suscripción (estructura) + CUIT/CUIL del comercio.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- plans: gratis / básico / intermedio / pro. Sin reglas duras por ahora (Q4-a):
-- el default es FREE sin limitaciones, y la estructura queda lista para ponerlas.
-- retention_days = días tras el CIERRE del evento hasta que se borra del sistema.
-- La fecha de borrado nunca puede ser anterior a la fecha de reclamo de premios.
-- ---------------------------------------------------------------------------
create table if not exists public.plans (
  code          text primary key,
  name          text not null,
  sort_order    int not null default 0,
  max_active_events int,           -- null = sin límite (todavía sin regla)
  max_participants_per_event int,  -- null = sin límite (todavía sin regla)
  retention_days int,              -- null = nunca borra
  description   text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  constraint plans_code_format check (code ~ '^[A-Z_]{3,20}$')
);

comment on table public.plans is
  'Planes de suscripción. Estructura preparada; reglas de límites pendientes (Q4-a).';

insert into public.plans (code, name, sort_order, max_active_events, max_participants_per_event, retention_days, description)
values
  ('FREE', 'Gratis', 1, null, null, 30, 'Gratis. Los eventos se borran 30 días después del cierre. Para conservarlos, mejorá el plan.'),
  ('BASIC', 'Básico', 2, null, null, 90, 'Básico.'),
  ('INTERMEDIATE', 'Intermedio', 3, null, null, 365, 'Intermedio.'),
  ('PRO', 'Pro', 4, null, null, null, 'Pro. Histórico completo, sin borrado.')
on conflict (code) do nothing;

-- Solo lectura pública (el comercio necesita ver su plan y las opciones).
alter table public.plans enable row level security;
drop policy if exists plans_select on public.plans;
create policy plans_select on public.plans for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- merchants.plan_code (default FREE) y merchants.tax_type (CUIT o CUIL).
-- tax_id ya existía desde 0002.
-- ---------------------------------------------------------------------------
alter table public.merchants
  add column if not exists plan_code text not null default 'FREE' references public.plans(code) on delete restrict;

alter table public.merchants
  add column if not exists tax_type text check (tax_type in ('CUIT','CUIL'));

comment on column public.merchants.tax_type is
  'CUIT si es comercio registrado, CUIL si es persona. tax_id es la clave y le da la responsabilidad fiscal correspondiente.';

create index if not exists merchants_plan_idx on public.merchants (plan_code);

-- Solo el OWNER cambia el plan de un comercio (defensa en profundidad además de la RPC).
create or replace function private.guard_merchant_plan()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.plan_code is distinct from old.plan_code
     and current_user not in ('postgres','service_role','supabase_admin') then
    raise exception 'PLAN_OWNER_ONLY'
      using errcode = '42501',
            detail  = 'El plan de un comercio sólo lo cambia el OWNER.';
  end if;
  return new;
end $$;

drop trigger if exists merchants_guard_plan on public.merchants;
create trigger merchants_guard_plan
  before update on public.merchants
  for each row execute function private.guard_merchant_plan();