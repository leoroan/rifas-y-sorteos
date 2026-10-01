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
| 0001 | `enums` | Esquemas `private`/`extensions`, `pgcrypto`, enums del dominio, trigger `updated_at` |
| 0002 | `tenancy` | `profiles`, `merchants`, `merchant_members`, RBAC (`roles`, `permissions`, `role_permissions`, `member_permissions`) |
| 0003 | `settings` | `system_settings`, `merchant_settings` |
| 0004 | `events` | `draw_sources`, `events`, `prizes`, `event_numbers` + triggers de inmutabilidad y transiciones |
| 0005 | `reservations` | `reservations`, `reservation_numbers`, `payment_receipts` |
| 0006 | `results` | `draw_results`, `event_winners` |
| 0007 | `terms_notifications_audit` | `terms_versions`, `terms_acceptances`, `notifications`, `audit_logs`, `security_blocks` |
| 0008 | `helpers` | Funciones de autorización en el esquema `private` (no expuesto a la API) |
| 0009 | `rls` | `enable row level security` + **todas** las policies + vistas públicas |
| 0010 | `grants` | Permisos por verbo: qué puede escribir el cliente y qué **sólo** por RPC |
| 0011 | `rpc_reservations` | `reservation_create` (CAS atómico), cancelar, expirar, comprobantes, revisión |
| 0012 | `rpc_events` | Alta/edición/publicación/cierre/cancelación de eventos y premios |
| 0013 | `rpc_admin` | OWNER: comercios, asignación de MERCHANT, settings, staff, bloqueos |
| 0014 | `rpc_draw` | Resultado del sorteo (`MANUAL`, `RANDOM_SEEDED`, `EXTERNAL_LOTTERY`) y ganadores |
| 0015 | `seed` | Roles, permisos, settings, loterías, textos legales de plantilla, **OWNER** |
| 0016 | `storage` | Buckets `receipts` (privado) y `public-assets`, con policies de Storage |
| 0017 | `cron` | `pg_cron`: expiración de reservas, sincronización de estados, purgas |

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