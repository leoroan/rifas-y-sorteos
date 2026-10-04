# Roles y Permisos

## Roles

| Rol | Vive en | Alcance |
|---|---|---|
| OWNER | profiles.platform_role | Toda la plataforma |
| MERCHANT | merchant_members.role=MERCHANT | Sólo su comercio |
| COLLABORATOR | merchant_members.role=COLLABORATOR | Sólo su comercio, según permisos |
| PARTICIPANT | Implícito (cualquiera) | Eventos donde no es staff |

## Permisos (18)

| Código | OWNER | MERCHANT | COLLABORATOR |
|---|:--:|:--:|:--:|
| event.view | ✔ | ✔ | ✔ |
| event.create | ✔ | ✔ | ✖ |
| event.update | ✔ | ✔ | ✖ |
| event.publish | ✔ | ✔ | ✖ |
| event.close | ✔ | ✔ | ✔* |
| event.cancel | ✔ | ✔ | ✖ |
| event.draw | ✔ | ✔ | ✖ |
| prize.manage | ✔ | ✔ | ✔* |
| reservation.view | ✔ | ✔ | ✔ |
| reservation.create | ✖ | ✖ | ✖ |
| reservation.confirm | ✔ | ✔ | ✔* |
| reservation.cancel | ✔ | ✔ | ✔* |
| payment.receipt.upload | ✖ | ✖ | ✖ |
| payment.receipt.review | ✔ | ✔ | ✔* |
| staff.manage | ✔ | ✔ | ✖ |
| staff.suspend | ✔ | ✔ | ✖ |
| stats.view | ✔ | ✔ | ✔* |
| merchant.manage | ✔ | ✖ | ✖ |

\* = delegable por el comerciante (dentro del techo del rol MERCHANT).

## Reglas clave

1. **Sólo el OWNER otorga MERCHANT** (RPC admin_assign_merchant, auditada).
2. **El staff de un comercio NO participa en sus propios sorteos** (RPC reservation_create, verificado en DB).
3. **Un colaborador nunca supera el techo del MERCHANT** (RPC staff_set_permission valida).
4. **El OWNER no participa** como staff: reserva como participante normal.
5. **JWT no lleva roles**: se leen de la base en cada request (RLS + helpers).

## Helper SQL

Toda la autorización pasa por funciones en el esquema private (no expuesto):

- is_owner() → bool
- is_merchant_of(merchant_id) → bool
- has_merchant_permission(merchant_id, permission) → bool
- is_event_staff(event_id) → bool
- is_merchant_staff_of_event(event_id, profile_id) → bool
- can_view_event(event_id) → bool
- event_is_open_now(event_id) → bool
- is_blocked(profile_id, merchant_id, event_id) → bool
