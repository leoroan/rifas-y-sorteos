import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getEventMerchant, getEventNumbersSummary, getEventPrizes } from '../../services/supabase/queries/events.js'
import { canNativeShare, copyToClipboard, eventUrl, nativeShare, shareText } from '../../lib/share.js'
import { showSuccess, showRpcError } from '../../lib/sweetalert.js'
import { Button } from '../ui/Button.jsx'

/*
 * Botón Compartir evento: genera el texto listo para WhatsApp/Telegram/etc. y
 * lo deja copiar, copiar el enlace, o compartir por Web Share API si existe.
 * Todo local: ninguna integración.
 */
export function ShareEventButton({ event, variant = 'outline', size = 'sm' }) {
  const [busy, setBusy] = useState(false)

  const { data: merchant } = useQuery({
    queryKey: ['event-merchant', event.id],
    queryFn: () => getEventMerchant(event.id),
  })
  const { data: prizes } = useQuery({
    queryKey: ['event-prizes', event.id],
    queryFn: () => getEventPrizes(event.id),
  })
  const { data: summary } = useQuery({
    queryKey: ['event-summary', event.id],
    queryFn: () => getEventNumbersSummary(event.id),
  })

  function build() {
    return shareText({ event, merchant, prizes, summary })
  }

  async function copyText() {
    setBusy(true)
    const ok = await copyToClipboard(build())
    setBusy(false)
    if (ok) showSuccess('Texto copiado', 'Pegalo en WhatsApp, Telegram, Instagram o donde quieras.')
    else showRpcError(new Error('No se pudo copiar'))
  }

  async function copyLink() {
    setBusy(true)
    const ok = await copyToClipboard(eventUrl(event))
    setBusy(false)
    if (ok) showSuccess('Enlace copiado')
    else showRpcError(new Error('No se pudo copiar'))
  }

  async function shareNative() {
    setBusy(true)
    await nativeShare({
      title: event.title,
      text: build(),
      url: eventUrl(event),
    })
    setBusy(false)
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Button variant={variant} size={size} onClick={copyText} loading={busy}>
        Compartir
      </Button>
      <Button variant="ghost" size={size} onClick={copyLink}>
        Copiar enlace
      </Button>
      {canNativeShare() && (
        <Button variant="ghost" size={size} onClick={shareNative}>
          Compartir en el dispositivo
        </Button>
      )}
    </div>
  )
}
