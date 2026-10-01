-- =============================================================================
-- 0010_grants.sql
-- Segunda barrera, independiente de RLS: RLS decide QUÉ FILAS, los GRANT
-- deciden QUÉ VERBOS. Si una policy se escribiera mal, un GRANT ausente igual
-- bloquea el ataque.
--
-- Regla del proyecto: TODA escritura de negocio pasa por RPC. Por eso las
-- tablas de eventos, números, reservas, resultados, roles, auditoría y
-- configuración NO tienen verbo de escritura para los clientes.
-- =============================================================================

revoke all on all tables in schema public from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lectura pública (las policies acotan las FILAS; la vista acota las COLUMNAS)
-- ---------------------------------------------------------------------------
grant select on public.public_merchants,
                public.public_events,
                public.public_event_numbers,
                public.public_prizes,
                public.public_event_winners
  to anon, authenticated;

grant select on public.draw_sources,
                public.roles,
                public.permissions,
                public.role_permissions,
                public.terms_versions,
                public.system_settings,
                public.merchants,
                public.events,
                public.prizes,
                public.draw_results,
                public.event_winners
  to anon, authenticated;

-- event_numbers: se otorgan las columnas UNA POR UNA, sin reservation_id.
-- RLS no filtra columnas; esto sí. Un participante puede ver que el 25 está
-- PAID, pero no quién lo tiene.
grant select (id, event_id, number, display_code, status, updated_at)
  on public.event_numbers to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lectura para usuarios con sesión (sean anónimos de Auth o registrados)
-- ---------------------------------------------------------------------------
grant select on public.profiles,
                public.merchant_members,
                public.member_permissions,
                public.reservations,
                public.reservation_numbers,
                public.payment_receipts,
                public.notifications,
                public.terms_acceptances,
                public.merchant_settings,
                public.security_blocks,
                public.audit_logs
  to authenticated;

-- ---------------------------------------------------------------------------
-- Escritura directa: sólo lo mínimo, y nada que toque dinero, estado o permisos
-- ---------------------------------------------------------------------------
-- Cada uno edita su propio nombre y teléfono (la policy limita la fila; el
-- trigger profiles_guard_privileges impide tocarse el rol o el estado).
grant update (display_name, phone, last_seen_at) on public.profiles to authenticated;

-- Marcar una notificación como leída. Nada más: no se puede reescribir el texto.
grant update (read_at, status) on public.notifications to authenticated;

-- Evidencia de aceptación: sólo alta, nunca modificación (tabla append-only).
grant insert on public.terms_acceptances to authenticated;

-- Metadata del comprobante: sólo alta. La policy exige ser el dueño de la
-- reserva; sin policy de UPDATE es imposible auto-aprobarse.
grant insert on public.payment_receipts to authenticated;

-- ---------------------------------------------------------------------------
-- Tablas SIN verbo de escritura para clientes (van sólo por RPC):
--   event_numbers, reservations, reservation_numbers, draw_results,
--   event_winners, audit_logs, security_blocks, system_settings,
--   merchant_settings, roles, permissions, role_permissions, draw_sources,
--   terms_versions, merchant_members, member_permissions
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Defensa en profundidad: el estado del comercio y su creador sólo los cambia
-- el OWNER, incluso si algún día se otorgara un GRANT de escritura.
-- ---------------------------------------------------------------------------
create or replace function private.guard_merchant_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin') then
    if new.status is distinct from old.status then
      raise exception 'MERCHANT_STATUS_OWNER_ONLY'
        using errcode = '42501',
              detail  = 'Solo el OWNER activa, suspende o cierra un comercio.';
    end if;
    if new.created_by is distinct from old.created_by then
      raise exception 'MERCHANT_CREATOR_IMMUTABLE'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists merchants_guard_status on public.merchants;
create trigger merchants_guard_status
  before update on public.merchants
  for each row execute function private.guard_merchant_status();