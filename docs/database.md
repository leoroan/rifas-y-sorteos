# Base de Datos

## Resumen

22 migraciones, 24 tablas, 31 RPCs públicas, ~40 funciones privadas.

## Entidades

| Tabla | Propósito |
|---|---|
| profiles | Espejo de auth.users con platform_role, status, is_anonymous |
| merchants | Comercios (tenants): nombre, slug, CUIT/CUIL, plan, contacto, pago |
| merchant_members | Staff: MERCHANT / COLLABORATOR por comercio |
| merchant_applications | Solicitudes para ser comerciante (fase 2) |
| roles / permissions / role_permissions | Catálogo RBAC |
| member_permissions | Overrides por colaborador (techo: MERCHANT) |
| plans | Planes de suscripción: FREE/BASIC/INTERMEDIATE/PRO + retention_days |
| events | Sorteos/rifas: tipo, estado, números, precios, ganador, legal |
| event_numbers | Una fila por número (CAS atómico) |
| prizes | Premios por evento |
| reservations | Hold de números por participante |
| reservation_numbers | Ledger histórico (quién tuvo cada número y cuándo) |
| payment_receipts | Metadata del comprobante (archivo en Storage privado) |
| draw_sources | Catálogo de loterías (flexible por jurisdicción) |
| draw_results | Resultado del sorteo con snapshots y seed |
| event_winners | Ganador por premio |
| terms_versions | Textos legales versionados |
| terms_acceptances | Evidencia de aceptación (append-only) |
| notifications | Bandeja + outbox |
| audit_logs | Operaciones que afectan dinero/participación/permisos (append-only) |
| security_blocks | Bloqueos por perfil o clave (seam antiabuso) |
| system_settings | Configuración global (techos que el comercio no supera) |
| merchant_settings | Overrides del comercio |

## Máquinas de estado

### Evento
DRAFT → PUBLISHED → OPEN → CLOSED → DRAWN (o → CANCELLED desde DRAFT/PUBLISHED/OPEN)

### Número
AVAILABLE → RESERVED → PAYMENT_SUBMITTED → PAID → WINNER

### Reserva
PENDING → PAYMENT_SUBMITTED → APPROVED | EXPIRED | REJECTED | CANCELLED

## Cargar migraciones

Ver supabase/README.md para el orden y las verificaciones.

Criterio: cada archivo se ejecuta en el SQL Editor, en orden, y es re-ejecutable.

## Verificación

node scripts/validate-sql.cjs supabase/migrations/*.sql  # sintaxis
node scripts/check-conflicts.cjs supabase/migrations/*.sql  # ON CONFLICT
