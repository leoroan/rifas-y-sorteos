# Design Brief — Plataforma de Sorteos y Rifas

> Documento para un equipo/agente de diseño. Contiene la descripción del producto,
> todas las vistas actuales con su funcionalidad, el sistema visual existente, y
> qué debe preservarse vs. qué puede rediseñarse libremente.
>
> Objetivo: producir un **sistema de diseño** (colores, tipografía, componentes,
> modales, cards, espaciado) que se aplique sobre lo construido sin romper la
> funcionalidad.

---

## 1. Qué es el producto

Una plataforma SaaS **multi-comercio** para gestionar **sorteos y rifas con números limitados**.

Un comerciante crea un sorteo, lo publica y comparte el enlace por el canal que quiera (WhatsApp, Telegram, Instagram). Los participantes eligen números, pagan por fuera de la app, suben el comprobante, el comercio lo valida, y al finalizar se determina el ganador.

**El canal de mensajería no es parte del sistema.** La plataforma es el sistema de registro: comercios, usuarios, roles, sorteos, números, reservas, comprobantes, premios, resultados, auditoría y configuración.

### La regla de diseño del producto

> **Estúpidamente sencilla de usar, pero no estúpidamente diseñada.**

La página pública de un sorteo tiene que entenderse en segundos por alguien que nunca usó la app. Todo lo demás (panel del comerciante, admin) puede ser más denso pero debe seguir siendo limpio y operativo.

---

## 2. Usuarios y roles

Hay 4 actores. El diseño debe darles contextos visualmente distintos sin parecer apps diferentes.

| Rol | Quién es | Qué ve |
|---|---|---|
| **Visitante público** | Cualquiera con el enlace | La página pública del sorteo, sin cuenta |
| **Participante registrado** | Cliente del sorteo | Reserva, sube comprobante, ve su historial y premios |
| **Comerciante / Colaborador** | El dueño o empleado del negocio | Panel operativo: eventos, reservas, comprobantes, equipo, resultado |
| **Owner** | El dueño de la plataforma | Administración global: comercios, solicitudes, loterías, usuarios, configuración, auditoría |

### Contextos visuales

- **Público (participante)**: la experiencia central. Mobile-first, enorme claridad, una sola acción importante por pantalla.
- **Operativo (comerciante)**: un dashboard de trabajo, más denso, pero limpio.
- **Administrativo (owner)**: gestión de tenants, con tabs/secciones.

---

## 3. Stack técnico (restricciones para el diseño)

- **React 18 + Vite** (SPA)
- **Tailwind CSS v4** — configuración CSS-first con `@theme` en `src/styles/tokens.css`. Todo el sistema de diseño se define ahí.
- **SweetAlert2** para confirmaciones destructivas, errores de negocio y éxitos de operaciones críticas.
- **HashRouter** — las URLs son `/#/ruta`.
- **Mobile-first** — la página pública del sorteo se diseña primero a 375px. En mobile hay una **barra de navegación inferior** fija.
- Sin librería de componentes: todos son propios.

### Archivos de estilo actuales

```
src/styles/
  tokens.css   # @theme de Tailwind v4: colores, tipografía, radios, sombras, spacing
  theme.css    # base: body, foco, utilidades
  globals.css  # imports
  sweetalert.css  # overrides de SweetAlert2
```

---

## 4. Sistema visual ACTUAL (estado real, para que el diseñador no parta de cero)

### Colores (tokens.css)

| Token | Uso | Valores |
|---|---|---|
| `ink-50 … ink-950` | Neutro/tinta principal (texto, bordes, fondos suaves) | escala de grises fríos |
| `paper-50 … paper-200` | Fondo de superficie (blanco cálido) | #fafbfc, #ffffff, #f2f4f7 |
| `accent-50 … accent-900` | **El único color de acento** (CTA, activo, links) | azul índigo (#3466f6 centro) |
| `available-*` | Estado: disponible | verde |
| `reserved-*` | Estado: reservado | ámbar |
| `submitted-*` | Estado: pago informado | azul |
| `paid-*` | Estado: pagado/confirmado | teal/esmeralda |
| `winner-*` | Estado: ganador | violeta |
| `error-*` | Error/destructivo | rojo |
| `warn-*` | Advertencia | ámbar |

**Decisión de identidad (preservar):** un neutro dominante + **un** color de acento + colores **exclusivamente semánticos** para estados. No usar gradientes decorativos ni más colores de acento.

### Tipografía

- Una sola familia: **system stack** (`ui-sans-serif, system-ui, ...`).
- **Números tabulares** para todos los datos numéricos (clase `.tnum`): números del sorteo, montos, contadores. Es un detalle de identidad importante: los números son el producto.

### Espaciado, radios, sombras

- Radios: `sm 6px`, `md 10px`, `lg 14px`. Contenidos, no extremos.
- Sombras discretas: `shadow-card` (sutil), `shadow-pop` (elevación). Nada exagerado.
- Botones grandes en acciones importantes (`size=lg`, h-13), secundarias discretas.

### Accesibilidad (no negociable)

- `focus-visible` siempre visible.
- Contraste AA.
- **Los estados NO se comunican sólo por color**: cada estado lleva texto y/o ícono (el número pagado tiene tilde, el reservado reloj, el ganador corona).
- `prefers-reduced-motion` respetado.

---

## 5. Componentes existentes (el inventario que el diseño debe cubrir)

| Componente | Uso actual |
|---|---|
| `Button` | variantes: primary, secondary, danger, ghost, outline. sizes: sm/md/lg. estado `loading` |
| `Input` | con label accesible, hint y error inline |
| `Badge` | estados con tono (neutral, accent, available, reserved, submitted, paid, winner, error, warn) |
| `Card` / `CardHeader` | contenedor principal de todo el contenido |
| `EmptyState` | cuando no hay datos |
| `LoadingState` / `Spinner` | carga |
| `FileUploader` | subir comprobante (preview de imagen, validación) |
| `NumbersGrid` | grilla de números de sólo lectura (eventos cerrados/terminados) |
| `ShareEventButton` | compartir evento (copiar texto, copiar enlace, Web Share API) |
| `NotificationBell` | campana con contador de no leídas |
| `ConfirmDialog` (vía SweetAlert2) | confirmaciones destructivas |

---

## 6. Vistas actuales con su funcionalidad (el mapa completo)

### 6.1 Home (`/`)

- **Hero**: "Sorteos claros, transparentes y verificables." + motivo visual de grilla de números con ganador destacado. CTAs: "Quiero publicar sorteos" (/solicitar) y "Explorar sorteos".
- **Trust strip**: 4 tarjetas (verificable, sin caos, privado por diseño, sin WhatsApp obligatorio).
- **Cómo funciona**: 3 pasos para comerciante, 3 para participante.
- **Sorteos activos**: grilla de eventos abiertos. Sección **Finalizados** aparte.
- **Estado visual**: es la primera impresión. Debe generar confianza y quedar grabada.

### 6.2 Página pública del sorteo (`/e/:slug`) — **la vista más importante**

Orden de contenido (mobile-first):
1. Comercio (nombre) + título del sorteo + badge de estado + botón Compartir
2. 3 stats: precio por número / números que quedan / total
3. Barra de progreso de disponibilidad
4. Premios (tarjetas)
5. Cómo se determina el ganador (aleatorio/manual/lotería)
6. **Selector de números** (grilla interactiva con estados)
7. Términos (desplegable) + checkbox de aceptación + botón Reservar
8. Confirmación de reserva (números, total, instrucciones de pago, plazo)
9. Si el evento terminó: **ganadores por puesto** + números de sólo lectura

**Reglas de diseño de esta vista:**
- Los números son botones de estado inequívoco (disponible/reservado/pago informado/pagado/cancelado/ganador).
- Multi-selección con contador y tope.
- Un visitante entiende en segundos qué se sortea, cuánto cuesta, cuándo cierra y cómo participar.

### 6.3 Mis participaciones (`/mis-participaciones`)

- Lista de reservas con badge de estado, cantidad de números, total, fecha.
- Cada reserva expandible: números, plazo, **FileUploader para subir comprobante** (si está pendiente), motivo si fue rechazada.
- Banner si es anónimo: invitación a crear cuenta.

### 6.4 Mi cuenta (`/perfil`)

- Nombre editable, email, rol, tipo de cuenta.
- Stats: participaciones, confirmadas, premios ganados.
- Lista de premios ganados.
- Nota de privacidad.

### 6.5 Autenticación

- `/ingresar`, `/registrarse`, `/recuperar`, `/recuperar/nueva`, `/crear-cuenta` (conversión anónimo→registrado), `/onboarding` (alta de comerciante aprobado).
- Todas usan el mismo `AuthCard` (logo, título, formulario centrado).

### 6.6 Notificaciones (`/notificaciones`)

- Lista por tipo (Reserva, Pago, Evento, Premio, Equipo, Cuenta).
- Leídas vs. no leídas destacadas. "Marcar todas como leídas".

### 6.7 Panel del comerciante (`/panel`) — **el área de trabajo**

- **Dashboard**: 4 stats (recaudación, comprobantes por revisar, reservas abiertas, eventos activos).
- **Comprobantes por revisar**: cada uno con ver archivo (URL firmada), aprobar, rechazar, pedir corrección.
- **Equipo**: colaboradores, agregar por email, suspender/quitar, permisos delegables.
- **Eventos agrupados por estado**: Borrador / En juego / Finalizados / Cancelados.
  - Borrador: agregar premios, publicar, compartir.
  - En juego: compartir, cerrar participación.
  - Finalizados: **cargar resultado** (manual por puesto / aleatorio / lotería).
- **Formulario de evento**: título, slug, números desde/hasta, precio, cierre, método de sorteo (+ regla y lotería si aplica).

### 6.8 Panel del Owner (`/admin`) — **administración global con tabs**

| Tab | Contenido |
|---|---|
| **Comercios** | Lista con búsqueda + filtro por estado. Al expandir: **actividad completa** del comercio (eventos, recaudación, participantes, comprobantes, premios, último acceso) |
| **Solicitudes** | Revisar solicitudes de comerciantes: aprobar (con plan) / rechazar (con motivo) |
| **Alta manual** | Crear comercio + asignar comerciante (flujo directo) |
| **Loterías** | Gestionar loterías de referencia (crear, activar/desactivar) |

### 6.9 Solicitud pública (`/solicitar`)

- Formulario para ser comerciante: nombre, apellido, email, negocio, DNI, CUIT/CUIL (con aviso de responsabilidad), teléfono, mensaje. Pantalla de éxito.

### 6.10 Onboarding (`/onboarding`)

- Para el solicitante aprobado: muestra el plan otorgado + aviso de retención, formulario completo del comercio, aceptación de ToS. Al confirmar: crea el comercio.

### 6.11 Legales (`/terminos`, `/privacidad`, `/reglas`)

- Textos legales versionados, con badge "plantilla".

---

## 7. Flujos clave (el diseño debe facilitarlos, no interrumpirlos)

### 7.1 Participar
```
enlace → evento → elegir números → registrarse → aceptar términos → reservar → pagar fuera → subir comprobante → esperar validación → confirmado → resultado
```

### 7.2 Operar (comerciante)
```
crear evento → premios → publicar → compartir → revisar comprobantes → aprobar → cerrar → cargar resultado → ganadores
```

### 7.3 Ser comerciante (tenant)
```
solicitar (formulario público) → OWNER aprueba → registrarse → onboarding (datos + plan + ToS) → comerciante
```

---

## 8. Lo que el diseño DEBE preservar (invariantes funcionales)

1. **Estados inequívocos**: cada estado (número, reserva, comprobante, evento) se reconoce por color + texto/ícono, nunca sólo por color.
2. **Un solo color de acento** para identidad; los demás colores son semánticos.
3. **Botones grandes** para acciones críticas (reservar, aprobar, publicar, crear).
4. **Errores inline** en formularios; **SweetAlert2** sólo para confirmaciones destructivas, errores de negocio y éxitos de operaciones críticas.
5. **Números tabulares** en todo dato numérico.
6. **Mobile-first** real: la vista pública del sorteo funciona perfecto a 375px; hay barra de navegación inferior en mobile.
7. **Accesibilidad**: labels, foco visible, contraste, estados no sólo por color.
8. **HashRouter**: los enlaces son `/#/ruta`.

## 9. Lo que puede rediseñarse libremente

- Paleta de colores exacta (mientras se mantenga "un neutro + un acento + semánticos").
- Tipografía (puede ser una familia variable elegida, manteniendo números tabulares).
- Espaciado, radios, sombras (manteniendo discretos).
- Composición de hero, cards, badges, modales.
- Ilustraciones/motivos visuales (el motivo de números es una idea, no un requisito).
- Componentes: pueden rediseñarse completamente visualmente, manteniendo su API/props.

---

## 10. Entregables esperados del equipo de diseño

1. **Design tokens** para Tailwind v4 (`@theme` en tokens.css): colores, tipografía, espaciado, radios, sombras.
2. **Sistema de componentes** (Button, Input, Badge, Card, Modal/Dialog, Table, EmptyState, FileUploader, NumberGrid, NotificationBell) con variantes y estados.
3. **Modales/Dialog** (hoy se usa SweetAlert2; evaluar si se reemplaza o se estiliza).
4. **Guía de estados**: cómo se ve cada estado (número, reserva, comprobante, evento, notificación) con color + ícono + texto.
5. **Mockups** de las 3 vistas clave: Home, Página pública del sorteo, Panel del comerciante.
6. **Tema de SweetAlert2** coherente con el sistema (si se conserva).
7. **Dark mode** (opcional): hoy solo hay modo claro.

---

## 11. Prioridades de diseño (qué importa más)

1. **La página pública del sorteo** — es el producto. Si sólo se mejora una cosa, es esta.
2. **El panel del comerciante** — es donde se trabaja todos los días.
3. **Home** — es la primera impresión y la conversión.
4. **Admin** — puede ser funcional y sobrio, no necesita brillo.

---

## 12. Notas finales

- El producto es **Argentino/español**: textos en español rioplatense, fechas en `es-AR`, moneda ARS por defecto.
- Los sorteos son **con números** — el motivo visual de los números es la identidad más fuerte del producto y puede ser la base de la marca.
- **No es un dashboard genérico**: la identidad visual debe sentirse propia, no un template de Tailwind.
