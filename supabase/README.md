# Migraciones de base de datos

Archivos SQL versionados para cargar en Supabase. **Todavía no fueron ejecutados contra ninguna base**: los escribí sin acceso a la DB, así que puede haber algún error de sintaxis o de orden. Si algo falla, pasame el mensaje exacto y lo corrijo (el archivo y la línea alcanzan).

## Cómo cargarlas

1. Supabase Dashboard → **SQL Editor** → *New query*.
2. Pegá el contenido de **un archivo**, ejecutá, verificá que diga *Success*.
3. Seguí con el siguiente, **respetando el orden de la tabla**. El orden importa: los enums van antes de las tablas, los helpers antes de las policies, los grants antes de las RPC.
4. Al terminar, corré las **consultas de verificación** de más abajo y pegame el resultado.

Los archivos están escritos para ser razonablemente re-ejecutables (los enums y las tablas usan guardas `if not exists`), pero si un archivo falla a mitad **no** conviene re-ejecutarlo entero: pasame el error primero.

## Orden de carga

| # | Archivo | Qué hace |
|---|---|---|
| 0001 | `enums` | Esquemas `private`/`extensions`, `pgcrypto`, 15 enums del dominio, trigger `updated_at` |
| 0002 | `tenancy` | `profiles`, `merchants`, `merchant_members`, RBAC (`roles`, `permissions`, `role_permissions`, `member_permissions`) |
| 0003 | `settings` | `system_settings`, `merchant_settings` + `fn_effective_setting` (techo global) |
| 0004 | `events` | `draw_sources`, `events`, `prizes`, `event_numbers` + triggers de inmutabilidad y transiciones |
| 0005 | `reservations` | `reservations`, `reservation_numbers` (ledger), `payment_receipts` |
| 0006 | `results` | `draw_results`, `event_winners` |
| 0007 | `terms_notifications_audit` | `terms_versions`, `terms_acceptances`, `notifications`, `audit_logs`, `security_blocks` + **FK diferidas** |
| 0008 | `helpers` | Funciones de autorización en el esquema `private` (no expuesto a la API) |
| 0009 | `rls` | `enable row level security` + **todas** las policies + vistas públicas + verificación |
| 0010 | `grants` | Permisos por verbo: qué puede escribir el cliente y qué **sólo** por RPC |
| 0011 | `rpc_reservations` | `reservation_create` (CAS atómico), expiración, cancelación, comprobantes, revisión |
| 0012 | `rpc_events` | Alta/edición/publicación/cierre/cancelación, premios y aceptación de términos |
| 0013 | `rpc_admin` | OWNER: comercios, asignación de MERCHANT, settings, staff, bloqueos |
| 0014 | `rpc_draw` | Resultado del sorteo (`MANUAL`, `RANDOM_SEEDED`, `EXTERNAL_LOTTERY`) y ganadores |
| 0015 | `seed` | Roles, permisos, configuración global, loterías, textos legales de plantilla, **OWNER** |
| 0016 | `storage_cron` | Buckets + policies de Storage, jobs de `pg_cron` y verificación final |
| 0017 | `merchant_invites` | Invitar staff por email aunque no esté registrado + activación automática al registrarse |

Total: **23 tablas** (+5 vistas públicas), ~15 enums y ~60 funciones.

## Antes de cargar: configuración del proyecto

Estos puntos **no** son SQL y hay que resolverlos en el dashboard:

| Tema | Dónde | Qué |
|---|---|---|
| **Anonymous sign-ins** | Authentication → Sign In / Providers | **Habilitar**. Sin esto el flujo de participante anónimo no funciona |
| Manual linking | Authentication → Settings | Habilitar, si vamos a usar la conversión anónimo→registrado |
| Email autoconfirm | Authentication → Providers → Email | Decidir: activado = menos fricción y sin estado intermedio (recomendado para el MVP) |
| Registro previo del OWNER | Authentication → Users | Tu usuario `leoroan+rifasysorteos@gmail.com` tiene que **existir** antes de cargar `0015_seed.sql` |
| Rate limit de anónimos | Authentication → Rate Limits | Revisar el valor (30/hora por defecto) |

## Después de cargar: verificación

**1. Enums y tablas creados (deberían ser 15 enums y 23 tablas):**

```sql
select count(*) as enums from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
 where n.nspname = 'public' and t.typtype = 'e';

select count(*) as tablas from information_schema.tables
 where table_schema = 'public' and table_type = 'BASE TABLE';
```

**2. RLS activo en todas las tablas (no debe haber ninguna con `false`):**

```sql
select relname, relrowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false;
```

**3. Hay policies en todas las tablas:**

```sql
select c.relname, count(p.polname) as policies
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policy p on p.polrelid = c.oid
 where n.nspname = 'public' and c.relkind = 'r'
 group by c.relname order by policies asc, c.relname;
```

**4. `pgcrypto` está donde el código lo espera** (se espera `extensions`):

```sql
select e.extname, n.nspname
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
 where e.extname = 'pgcrypto';
```

**5. El OWNER quedó bien sembrado:**

```sql
select id, email, platform_role, status from public.profiles
 where platform_role = 'OWNER';
```

**6. Los buckets existen y `receipts` es privado:**

```sql
select id, name, public from storage.buckets order by name;
```

## Qué mandarme si algo falla

El mensaje de error completo (`ERROR: ...` con `LINE` y `HINT`), y el nombre del archivo. No hace falta que corrijas nada.

## Lo que viene después de esta tanda

Tests de RLS y de concurrencia en `supabase/tests/`: los 12 casos críticos (§20 del documento de arquitectura), incluyendo la prueba de dos reservas simultáneas sobre el mismo número. Esos tests son la garantía real de que la seguridad quedó bien, y son el paso siguiente a que las migraciones carguen sin error.

## Verificación antes de cargar

Dos chequeos estáticos, sin necesidad de base de datos ni credenciales. Conviene correrlos antes de pegar cualquier archivo en el SQL Editor:

```bash
node scripts/validate-sql.js supabase/migrations/*.sql    # sintaxis real (libpg_query) + balance PL/pgSQL
node scripts/check-conflicts.js supabase/migrations/*.sql # cada ON CONFLICT tiene su índice único
```

- **`validate-sql.js`** parsea **cada sentencia** con el parser real de PostgreSQL y reporta archivo y línea. También verifica que los bloques `begin/end`, `if/end if`, `loop/end loop` de cada función estén balanceados (un truncado de archivo no lo detecta un parser SQL).
- **`check-conflicts.js`** compara cada `ON CONFLICT (cols)` contra los índices únicos declarados. Previene el error `42P10`, que es fácil de introducir al escribir un índice de expresión (`lower(col)`) y usar `ON CONFLICT (col)`.

Requieren `pgsql-parser` instalado (`npm i --no-save pgsql-parser`). Son sólo para desarrollo: no forman parte del bundle ni del deploy.

## Si un archivo falla a mitad de camino

1. Pegame el error tal cual (`ERROR: … LINE … HINT`).
2. Mientras tanto, **no** re-ejecutes el archivo completo si falló en el medio: primero hay que ver qué alcanzó a aplicarse.
3. Los archivos están escritos para ser re-ejecutables (`if not exists`, `drop trigger if exists`, `create or replace`), así que recargar uno ya aplicado es seguro.

### Recargas necesarias por correcciones posteriores

| Archivo | Motivo | ¿Urgente? |
|---|---|---|
| `0004_events.sql` | El índice `draw_sources_code_uk` cambió de `lower(code)` a `code`; incluye el `drop index` para que la recarga tome efecto | **Sí**, sin esto `0015_seed.sql` falla con `42P10` |

## Decisión de diseño que conviene tener presente al cargar

- **Toda escritura de negocio pasa por RPC.** Las tablas de eventos, números, reservas, resultados, roles, auditoría y configuración **no tienen** `INSERT`/`UPDATE` para los clientes. Si algo "no se puede guardar" desde el frontend, es por diseño: hay que llamar la RPC.
- **`event_numbers`: la columna `reservation_id` no se otorga** (grant por columna). Un participante ve que el 25 está `PAID`, pero no quién lo tiene. Para leer el grid, usar la vista `public_event_numbers`.
- **El sorteo aleatorio es de un solo tiro.** `draw_results` tiene `UNIQUE(event_id)` y no admite `UPDATE`/`DELETE` para clientes. Si el resultado no convence, la salida es cancelar el evento (auditado), no reintentar.
- **El seed lo genera el servidor.** La RPC ignora cualquier seed o número que mande el cliente en modo `RANDOM_SEEDED`. La fórmula y el seed quedan publicados para que cualquiera verifique el resultado.
- **Los holds vencidos se liberan solos.** `reservations_expire_stale()` corre por `pg_cron` **y** se invoca de forma defensiva dentro de las RPC, así que el sistema es correcto incluso si `pg_cron` no está activo.
- **Un usuario anónimo no se borra automáticamente.** `admin_anonymous_retention_report()` dice cuántos candidatos hay; borrarlos es una decisión explícita del OWNER (borrar usuarios de `auth.users` es irreversible).
- **El comerciante no puede aflojar un techo global:** `merchant_set_setting` **rechaza** con `SETTING_EXCEEDS_GLOBAL_LIMIT`, no recorta en silencio.
- **Los textos legales del seed son plantillas** marcadas como `1.0-draft` / "REQUIERE REVISIÓN LEGAL". La legalidad se revisa después (confirmado por el OWNER). El sistema registra `legal_status` y no opina.