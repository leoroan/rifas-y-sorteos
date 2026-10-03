import { env } from '../app/config/env.js'

/*
 * Compartir sin integrar WhatsApp: se genera el texto LOCALMENTE con los datos
 * ya cargados del evento. Tres salidas: copiar texto, copiar enlace, y Web
 * Share API cuando existe (móvil). Nada se envía a ningún proveedor.
 */

export function eventUrl(event) {
  return `${env.appUrl}/#/e/${event.slug}`
}

export function shareText({ event, merchant, prizes = [], summary = null }) {
  const prize = prizes?.[0]
  const total = event.numbers_to - event.numbers_from + 1
  const disponibles = summary?.available != null ? summary.available : total
  const cierre = new Date(event.participation_ends_at).toLocaleString('es-AR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })

  return [
    `🎟️ SORTEO ACTIVO — ${merchant?.name ?? 'Sorteo'}`,
    '',
    prize ? `Premio: ${prize.title}` : null,
    event.price_per_number > 0 ? `Valor por número: $${event.price_per_number} ${event.currency}` : 'Gratis',
    `Números disponibles: ${event.numbers_from} al ${event.numbers_to} (quedan ${disponibles})`,
    '',
    'Participá acá:',
    eventUrl(event),
    '',
    `Cierra: ${cierre}`,
  ]
    .filter(Boolean)
    .join('\n')
}

export async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    // Fallback para navegadores viejos o sin permisos de clipboard.
    const ta = document.createElement('textarea')
    ta.value = text
    ta.style.position = 'fixed'
    ta.style.opacity = '0'
    document.body.appendChild(ta)
    ta.select()
    let ok = false
    try {
      ok = document.execCommand('copy')
    } catch {
      // Si el navegador no lo permite, ok queda en false.
    }
    document.body.removeChild(ta)
    return ok
  }
}

export function canNativeShare() {
  return typeof navigator !== 'undefined' && typeof navigator.share === 'function'
}

export async function nativeShare({ title, text, url }) {
  if (!canNativeShare()) return false
  try {
    await navigator.share({ title, text, url })
    return true
  } catch (e) {
    // El usuario canceló el diálogo nativo: no es un error.
    if (e?.name === 'AbortError') return false
    return false
  }
}
