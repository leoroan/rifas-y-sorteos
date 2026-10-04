# Reglas de Negocio

## Sorteos

### Creación
1. Un comerciante crea un evento en DRAFT
2. Define: números (from/to), precio, premios, método de sorteo, cierre
3. Agrega premios (sólo en DRAFT)
4. Publica: se materializan los números y se congela el rango (numbers_locked_at)

### Participación
1. El participante ve el evento sin cuenta
2. Para reservar debe registrarse (email)
3. Acepta términos (checkbox, queda auditado con hash de versión)
4. Reserva números (RPC atómica)
5. Recibe instrucciones de pago del comercio
6. Sube comprobante (bucket privado + metadata)

### Validación
1. El comercio ve comprobantes pendientes
2. Aprueba, rechaza o pide corrección (con motivo)
3. Al aprobar: números pasan a PAID

### Resultado
1. El evento cierra (automático por fecha o manual)
2. El comercio carga el resultado:
   - MANUAL: números por puesto (1°, 2°, 3°...)
   - RANDOM_SEEDED: el sistema sortea entre pagados (seed verificable)
   - EXTERNAL_LOTTERY: extracto de lotería externa
3. Se publican ganadores y se notifican

### Retención
Según el plan del comercio, los eventos se borran X días tras el cierre.
La fecha de borrado nunca es anterior al reclamo de premios.

## Personal del comercio

Quienes trabajan en un comercio NO participan en sus sorteos (pero sí en otros).
Se verifica en la RPC de reserva, no en React.

## Configuración

El OWNER define techos globales. El comercio puede bajar, nunca subir.
merchant_set_setting rechaza (SETTING_EXCEEDS_GLOBAL_LIMIT), no recorta.

## Invitaciones

- OWNER invita por email a comerciantes/colaboradores
- La invitación se activa automáticamente al registrarse
- El OWNER puede revocar
