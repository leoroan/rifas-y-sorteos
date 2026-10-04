# Seguridad

## Principio

La base de datos es la frontera de seguridad. React decide qué mostrar, no qué permitir.

## Capas

1. **RLS** en todas las tablas (habilitado automáticamente, verificado en cada migración)
2. **GRANTs** por verbo: las tablas críticas no tienen INSERT/UPDATE para clientes
3. **RPCs** security definer con search_path='' para toda operación de negocio
4. **Triggers** que hacen cumplir inmutabilidad (números, términos, transiciones)
5. **Constraints** que validan rangos, formatos y coherencia

## Multi-tenancy

- Cada tabla con merchant_id tiene RLS que impide cross-tenant
- El merchant_id se deriva de la fila real o auth.uid(), nunca del cliente
- Storage paths incluyen merchant_id y la RLS de Storage valida el path

## Concurrencia

La reserva usa UPDATE...WHERE status='AVAILABLE' (compare-and-swap):
- Una sola sentencia para todos los números pedidos
- All-or-nothing: si alguno falla, se liberan todos
- El perdedor recibe la lista exacta de números perdidos

## Antiabuso

Configurado en system_settings (Owner puede editar):
- max_numbers_per_reservation (techo global)
- max_open_reservations_per_event
- max_reservations_per_window (rate limit)
- max_expired_reservations (cooldown)
- Bloqueos temporales automáticos

## Lo que NO está

- service_role NUNCA en el frontend
- JWT no lleva roles (se leen de la base)
- IP cruda NUNCA se guarda (sólo hash con TTL)
- Comprobantes en bucket privado con URLs firmadas

## Participación registrada

Los usuarios anónimos pueden VER eventos pero NO reservar (Q1: opción a).
Se hace cumplir con un trigger en la tabla reservations.
