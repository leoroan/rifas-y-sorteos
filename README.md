# rifas-y-sorteos

Plataforma SaaS **multicomercio** para gestionar sorteos y rifas con números limitados.

Un comerciante crea un sorteo, publica un enlace y lo comparte por WhatsApp, Telegram, Instagram o donde quiera. Los participantes (registrados **o anónimos**) reservan números, suben el comprobante de pago y el comercio lo valida. El canal de mensajería es externo: **la plataforma no depende de WhatsApp**.

> Regla rectora: **estúpidamente sencilla de usar, no estúpidamente diseñada.**

## Estado actual

**Fase 1 — Arquitectura. Completada, a la espera de confirmación.**

Todavía **no hay código de aplicación**: primero el diseño, después la implementación, como corresponde a un sistema donde el dinero y la participación son el centro.

- 📄 **[Documento de arquitectura](docs/architecture.md)** — modelo de datos, roles, permisos, máquinas de estado, concurrencia, RLS, JWT, usuarios anónimos, antiabuso, frontend, deployment, legal, testing y plan de fases.
- ✅ **Pendiente de tu parte:** las 12 decisiones abiertas (§21) y los 5 blockers técnicos (§22) del documento.
- 🚧 **Próximo paso (Fase 2):** migraciones de Supabase — tablas, constraints, índices, triggers, RLS, policies, grants y funciones RPC.

## Stack

React · Vite · JavaScript/ESM · Tailwind CSS v4 · SweetAlert2 · Supabase (Auth, PostgreSQL, Storage) · GitHub Actions + GitHub Pages.

## Lo que define este proyecto

- **La base de datos es la frontera de seguridad.** La autorización real vive en RLS, constraints y funciones RPC. React sólo decide qué mostrar.
- **Una reserva es atómica.** Dos personas pidiendo el mismo número a la vez: una lo obtiene, la otra recibe un error claro. Se resuelve con un `UPDATE ... WHERE status='AVAILABLE'` en PostgreSQL, no con un `SELECT` previo.
- **El personal de un comercio no puede participar en sus propios sorteos** (y sí en los de otros). La regla se evalúa en el RPC, no en el navegador.
- **Nadie modifica la cantidad de números una vez publicado el sorteo**, ni siquiera llamando la API directamente.
- **El comerciante nunca puede aflojar una regla global de seguridad.**
- **Sólo el OWNER puede crear comerciantes**, y queda auditado quién, a quién y cuándo.
- **Los comprobantes de pago viven en un bucket privado** con URLs firmadas efímeras.
- **Ningún secreto llega al navegador.** Sólo la publishable key.

## Configuración de entorno

Copiar `.env.example` a `.env` y completar:

```env
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_KEY=
VITE_PUBLIC_APP_URL=
```

El `.env` está en `.gitignore`. Recordá que **todo lo que empieza con `VITE_` es público** una vez compilado: ahí sólo va material público por diseño.

## Estructura del repositorio

```text
docs/           Documentación de arquitectura y decisiones
src/            (Fase 3) Aplicación React, modularizada por dominio
supabase/       (Fase 2) Migraciones y tests de RLS
.github/        (Fase 9) Workflow de deploy a GitHub Pages
```

## Deployment

GitHub Pages mediante GitHub Actions. Sólo variables públicas (`vars.*`) en el build; el `service_role` y cualquier otro secreto quedan fuera del repositorio y del workflow.