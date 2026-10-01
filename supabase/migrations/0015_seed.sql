-- =============================================================================
-- 0015_seed.sql
-- Datos mínimos para que la plataforma funcione: RBAC, configuración global,
-- loterías, textos legales de PLANTILLA y el OWNER.
-- Idempotente: se puede volver a ejecutar.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Roles y permisos
-- ---------------------------------------------------------------------------
insert into public.roles (code, label, scope, sort_order) values
  ('OWNER',       'Administrador de la plataforma', 'PLATFORM', 1),
  ('MERCHANT',    'Comerciante',                    'MERCHANT', 2),
  ('COLLABORATOR','Colaborador',                    'MERCHANT', 3),
  ('PARTICIPANT', 'Participante',                   'PLATFORM', 4)
on conflict (code) do update
   set label = excluded.label, scope = excluded.scope, sort_order = excluded.sort_order;

insert into public.permissions (code, description, scope) values
  ('event.view',             'Ver eventos',                             'EVENT'),
  ('event.create',           'Crear eventos',                           'MERCHANT'),
  ('event.update',           'Editar eventos',                          'MERCHANT'),
  ('event.publish',          'Publicar eventos',                        'MERCHANT'),
  ('event.close',            'Cerrar participación',                    'MERCHANT'),
  ('event.cancel',           'Cancelar eventos',                        'MERCHANT'),
  ('event.draw',             'Registrar resultado y publicar ganadores', 'MERCHANT'),
  ('prize.manage',           'Administrar premios',                     'MERCHANT'),
  ('reservation.create',     'Reservar números',                        'EVENT'),
  ('reservation.view',       'Ver reservas',                            'MERCHANT'),
  ('reservation.confirm',    'Confirmar reservas',                      'MERCHANT'),
  ('reservation.cancel',     'Cancelar reservas',                       'MERCHANT'),
  ('payment.receipt.upload', 'Subir comprobante de pago',               'EVENT'),
  ('payment.receipt.review', 'Revisar comprobantes de pago',            'MERCHANT'),
  ('staff.manage',           'Administrar colaboradores y permisos',     'MERCHANT'),
  ('staff.suspend',          'Suspender colaboradores',                 'MERCHANT'),
  ('stats.view',             'Ver estadísticas',                        'MERCHANT'),
  ('merchant.manage',        'Administrar el comercio y la plataforma',  'PLATFORM')
on conflict (code) do update
   set description = excluded.description, scope = excluded.scope;

-- Matriz por defecto. El OWNER NO recibe reservation.create ni
-- payment.receipt.upload: para participar lo hace como un participante normal.
delete from public.role_permissions rp
 where rp.role_code in ('OWNER','MERCHANT','COLLABORATOR','PARTICIPANT');

insert into public.role_permissions (role_code, permission_code)
select 'OWNER', p.code from public.permissions p
 where p.code not in ('reservation.create','payment.receipt.upload');

insert into public.role_permissions (role_code, permission_code)
select 'MERCHANT', p.code from public.permissions p
 where p.code in ('event.view','event.create','event.update','event.publish','event.close',
                  'event.cancel','event.draw','prize.manage','reservation.view',
                  'reservation.confirm','reservation.cancel','payment.receipt.review',
                  'staff.manage','staff.suspend','stats.view');

insert into public.role_permissions (role_code, permission_code)
select 'COLLABORATOR', p.code from public.permissions p
 where p.code in ('event.view','event.close','prize.manage','reservation.view',
                  'reservation.confirm','reservation.cancel','payment.receipt.review',
                  'stats.view');

insert into public.role_permissions (role_code, permission_code)
select 'PARTICIPANT', p.code from public.permissions p
 where p.code in ('event.view','reservation.view','reservation.create',
                  'reservation.cancel','payment.receipt.upload');

-- ---------------------------------------------------------------------------
-- Configuración global (techos que el comercio NO puede superar)
-- direction: ceiling = el comercio puede bajar, nunca subir.
-- ---------------------------------------------------------------------------
insert into public.system_settings
  (key, value, value_type, direction, min_value, max_value, description,
   is_public, is_owner_only, editable_by_merchant)
values
  ('limits.max_numbers_per_reservation', '20'::jsonb, 'int', 'ceiling', 1, 1000,
   'Máximo de números por reserva (techo que cada comercio puede bajar).', true, false, true),
  ('limits.max_numbers_per_event', '20'::jsonb, 'int', 'ceiling', 1, 1000,
   'Máximo de números por participante en un mismo evento.', true, false, true),
  ('limits.max_reservation_ttl', '"48 hours"'::jsonb, 'interval', 'ceiling', null, null,
   'Duración máxima del hold de una reserva.', false, false, true),
  ('limits.max_review_ttl', '"168 hours"'::jsonb, 'interval', 'ceiling', null, null,
   'Plazo máximo para que el comercio revise un comprobante.', false, false, true),
  ('abuse.max_open_reservations_per_event', '5'::jsonb, 'int', 'ceiling', 1, 200,
   'Reservas vivas simultáneas por participante en un evento.', false, true, false),
  ('abuse.max_open_reservations', '10'::jsonb, 'int', 'ceiling', 1, 500,
   'Reservas vivas simultáneas por participante en toda la plataforma.', false, true, false),
  ('abuse.max_reservations_per_window', '10'::jsonb, 'int', 'ceiling', 1, 200,
   'Reservas permitidas por ventana de tiempo (rate limit).', false, true, false),
  ('abuse.rate_window_minutes', '60'::jsonb, 'int', 'ceiling', 1, 1440,
   'Largo de la ventana de rate limit, en minutos.', false, true, false),
  ('abuse.max_expired_reservations', '5'::jsonb, 'int', 'ceiling', 1, 100,
   'Reservas vencidas toleradas antes del cooldown.', false, true, false),
  ('abuse.failed_window_hours', '24'::jsonb, 'int', 'ceiling', 1, 720,
   'Ventana en horas para contar reservas fallidas.', false, true, false),
  ('abuse.auto_block_hours', '24'::jsonb, 'int', 'ceiling', 1, 720,
   'Duración del bloqueo automático por abuso.', false, true, false),
  ('abuse.captcha_mode', '"off"'::jsonb, 'text', 'none', null, null,
   'off | turnstile. Requiere verificación server-side para poder activarse.', false, true, false),
  ('storage.max_receipt_bytes', '8388608'::jsonb, 'int', 'ceiling', 1024, 20971520,
   'Tamaño máximo del comprobante, en bytes.', true, true, false),
  ('storage.allowed_mime_types',
   '["image/jpeg","image/png","image/webp","application/pdf"]'::jsonb, 'json', 'none', null, null,
   'Formatos aceptados para comprobantes.', true, true, false),
  ('security.retention.anonymous_days', '90'::jsonb, 'int', 'ceiling', 7, 365,
   'Días que se conserva un usuario anónimo sin actividad ni reservas vivas.', false, true, false),
  ('security.retention.ip_hash_days', '30'::jsonb, 'int', 'ceiling', 1, 90,
   'Días de retención del hash de IP. Nunca se guarda la IP cruda.', false, true, false),
  ('legal.require_authorized_status', 'false'::jsonb, 'bool', 'none', null, null,
   'Si es true, no se publica un evento sin legal_status AUTHORIZED o EXEMPT.', false, true, false),
  ('legal.disclaimer',
   '"La plataforma no opina sobre la legalidad de un sorteo. Verificá la normativa de tu jurisdiccion antes de publicar."'::jsonb,
   'text', 'none', null, null,
   'Advertencia legal mostrada a los comercios al publicar.', true, true, false)
on conflict (key) do update
   set description = excluded.description,
       value_type  = excluded.value_type,
       direction   = excluded.direction,
       is_public   = excluded.is_public,
       is_owner_only = excluded.is_owner_only,
       editable_by_merchant = excluded.editable_by_merchant;

-- ---------------------------------------------------------------------------
-- Catálogo de loterías. Son EJEMPLOS genéricos: el OWNER debe revisarlos y
-- ajustarlos a la jurisdicción real donde opere. (LOTERIA_* queda inactiva
-- a propósito hasta que se confirme que aplica.)
-- ---------------------------------------------------------------------------
insert into public.draw_sources (code, name, kind, jurisdiction, shifts, timezone, is_active, sort_order)
values
  ('SORTEO_PROPIO',     'Sorteo propio / presencial', 'PRIVATE',    null, array['UNICA'], 'America/Argentina/Buenos_Aires', true,  1),
  ('LOTERIA_NACIONAL',  'Lotería Nacional',           'NATIONAL',   'AR', array['MATUTINA','VESPERTINA','NOCTURNA'], 'America/Argentina/Buenos_Aires', false, 2),
  ('LOTERIA_PROVINCIAL','Lotería Provincial',         'PROVINCIAL', 'AR', array['MATUTINA','VESPERTINA','NOCTURNA'], 'America/Argentina/Buenos_Aires', false, 3)
on conflict (code) do update
   set name = excluded.name, kind = excluded.kind, jurisdiction = excluded.jurisdiction,
       shifts = excluded.shifts, sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Textos legales de PLANTILLA.
-- ADVERTENCIA: son borradores. NO vuelven legal ningún sorteo y deben ser
-- revisados por un profesional antes de un uso comercial. El contenido se
-- versiona: nunca se sobrescribe un texto ya publicado.
-- ---------------------------------------------------------------------------
do $$
declare
  v_terms text;
  v_privacy text;
  v_rules text;
begin
  v_terms := 'PLANTILLA — REQUIERE REVISIÓN LEGAL

1. Objeto
Esta plataforma es una herramienta de registro y gestión de sorteos y rifas. No organiza, administra ni fiscaliza los sorteos publicados por los comercios, y no es parte de la relación entre el comercio y el participante.

2. Responsabilidad del comercio
Cada comercio es el único responsable del sorteo que publica: de su legalidad, de la veracidad de los premios, de su entrega, de la atención de los participantes y del cumplimiento de la normativa provincial y nacional aplicable a juegos de azar y sorteos con contraprestación.

3. Autorizaciones
Los sorteos con precio de participación pueden requerir autorización previa según la jurisdicción, la modalidad, el tipo de premio y el mecanismo de adjudicación. La plataforma no tramita ni verifica esas autorizaciones: sólo permite registrar el estado legal declarado por el comercio.

4. Participación
El participante declara tener capacidad legal para contratar y haber leído las condiciones generales y las particulares del evento. Cada sorteo puede establecer condiciones propias.

5. Pagos
Los pagos se realizan fuera de la plataforma, por los medios que indique el comercio. La plataforma sólo registra reservas y comprobantes, y no procesa, retiene ni reembolsa dinero.

6. Adjudicación
El mecanismo de determinación del ganador se informa en cada evento y queda registrado con su evidencia. Los resultados publicados son auditables.

7. Sin garantía
La plataforma se ofrece "tal cual". No se garantiza disponibilidad ininterrumpida ni ausencia de errores.';

  v_privacy := 'PLANTILLA — REQUIERE REVISIÓN LEGAL

1. Datos que se guardan
- Cuenta: identificador de usuario, email (si se registró) y nombre para mostrar.
- Participación: reservas, números, estado de pago y comprobantes subidos.
- Aceptación de condiciones: versión exacta del texto aceptado, fecha y hash del contenido.
- Auditoría: operaciones que afectan dinero, participación, permisos o resultados.

2. Datos que NO se guardan
- No se guarda la dirección IP en forma legible. Si se usa como señal antiabuso, se guarda un hash con sal y por tiempo limitado.
- No se piden documentos, domicilio ni fecha de nacimiento para participar.

3. Usuarios anónimos
Se puede participar sin crear una cuenta tradicional. En ese caso se crea una cuenta anónima que permite reservar y subir comprobantes. El usuario puede convertirla en cuenta permanente y conservar todo su historial.

4. Comprobantes
Se almacenan en un espacio privado. Sólo pueden verlos el propio participante y el comercio autorizado, mediante enlaces temporales firmados. Nunca son públicos.

5. Conservación
Los datos de participación y auditoría se conservan mientras exista la relación y por el plazo necesario para responder reclamos y cumplir obligaciones legales. Los usuarios anónimos inactivos se eliminan periódicamente.

6. Derechos
El usuario puede solicitar acceso, rectificación y supresión de sus datos. La supresión de datos que integran la auditoría de un resultado o de un pago se resuelve por anonimización, para no destruir evidencia.

7. Responsable
El comercio es responsable de los datos de sus participantes. La plataforma actúa como proveedor técnico.';

  v_rules := 'PLANTILLA — REQUIERE REVISIÓN LEGAL

1. Cómo participar
Elegí los números que quieras, confirmá la reserva y aceptá las condiciones. Los números quedan reservados por tiempo limitado.

2. Reserva y pago
La reserva no equivale a un pago. Tenés que subir el comprobante dentro del plazo indicado. Si el plazo vence, los números vuelven a estar disponibles.

3. Validación
El comercio revisa el comprobante y puede aprobarlo, rechazarlo o pedirte una corrección. Si rechaza, los números se liberan. Si pide una corrección, conservás los números con un plazo nuevo.

4. Límites
Cada evento define cuántos números podés reservar, cuánto dura la reserva y cuántos números hay en total. También se aplican límites de la plataforma para evitar el abuso.

5. Personal del comercio
Quienes trabajan en un comercio no pueden participar en los sorteos de ese comercio. Sí pueden participar en los de otros comercios.

6. Resultado
El mecanismo para determinar el ganador se informa en cada evento. Cuando el sorteo es aleatorio, se publica el seed y la fórmula para que cualquiera pueda verificarlo.

7. Cancelación
Si un evento se cancela, se avisa a los participantes y se liberan las reservas sin pago confirmado. Lo ya pagado se resuelve directamente con el comercio.';

  insert into public.terms_versions
    (scope, event_id, kind, version, title, content, content_hash, published_at, is_current)
  values
    ('GLOBAL', null, 'TERMS', '1.0-draft', 'Términos y condiciones',
     v_terms, encode(extensions.digest(v_terms, 'sha256'), 'hex'), now(), true),
    ('GLOBAL', null, 'PRIVACY', '1.0-draft', 'Política de privacidad',
     v_privacy, encode(extensions.digest(v_privacy, 'sha256'), 'hex'), now(), true),
    ('GLOBAL', null, 'PARTICIPATION_RULES', '1.0-draft', 'Reglas de participación',
     v_rules, encode(extensions.digest(v_rules, 'sha256'), 'hex'), now(), true)
  on conflict do nothing;
end $$;

-- ---------------------------------------------------------------------------
-- OWNER INICIAL
-- Se siembra por UUID explícito: nadie puede auto-asignarse este rol.
-- Si el usuario todavía no existe en auth.users, avisa y NO falla: registrate
-- con ese email y volvé a ejecutar sólo este bloque.
-- ---------------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  update public.profiles p
     set platform_role = 'OWNER', status = 'ACTIVE'
   where p.id = 'f8cea989-2f3a-4647-ad5a-74101c854671';

  get diagnostics v_n = row_count;

  if v_n = 0 then
    raise notice 'ATENCION: el usuario OWNER (f8cea989-2f3a-4647-ad5a-74101c854671) todavia no existe en auth.users. Registrate con leoroan+rifasysorteos@gmail.com y volve a ejecutar SOLO este bloque.';
  else
    raise notice 'OK: OWNER asignado a f8cea989-2f3a-4647-ad5a-74101c854671 (leoroan+rifasysorteos@gmail.com).';
  end if;
end $$;