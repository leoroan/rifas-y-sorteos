import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { listEventPrizes } from '../../services/supabase/queries/merchant.js'
import { callRpc } from '../../lib/rpc.js'
import { confirmDanger, showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { EVENT_STATUS } from '../../constants/statuses.js'

function PublishButton({ event }) {
  const qc = useQueryClient()
  const { data: prizes } = useQuery({
    queryKey: ['event-prizes-manage', event.id],
    queryFn: () => listEventPrizes(event.id),
  })

  const publish = useMutation({
    mutationFn: () => callRpc('event_publish', { p_event_id: event.id }),
    onSuccess: () => {
      showSuccess('¡Evento publicado!', 'Ya se puede compartir el enlace y reservar números.')
      qc.invalidateQueries({ queryKey: ['merchant-events', event.merchant_id] })
    },
    onError: (e) => showRpcError(e, 'No se pudo publicar'),
  })

  const hasPrizes = (prizes || []).some((p) => p.status === 'ACTIVE')

  return (
    <div className="flex items-center gap-2">
      {!hasPrizes && <span className="text-xs text-warn-700">Falta al menos un premio para publicar</span>}
      <Button
        size="sm"
        disabled={!hasPrizes || publish.isPending}
        loading={publish.isPending}
        onClick={() => publish.mutate()}
      >
        Publicar
      </Button>
    </div>
  )
}

export function EventManageCard({ event }) {
  const qc = useQueryClient()
  const [prizeTitle, setPrizeTitle] = useState('')
  const [adding, setAdding] = useState(false)
  const [busy, setBusy] = useState(false)

  const { data: prizes } = useQuery({
    queryKey: ['event-prizes-manage', event.id],
    queryFn: () => listEventPrizes(event.id),
  })

  const isDraft = event.status === EVENT_STATUS.DRAFT

  async function addPrize(e) {
    e.preventDefault()
    if (!prizeTitle.trim()) return
    setBusy(true)
    try {
      await callRpc('prize_upsert', {
        p_event_id: event.id,
        p_prize_id: null,
        p_payload: { title: prizeTitle.trim(), position: (prizes?.length || 0) + 1 },
      })
      setPrizeTitle('')
      setAdding(false)
      qc.invalidateQueries({ queryKey: ['event-prizes-manage', event.id] })
      showSuccess('Premio agregado')
    } catch (err) {
      showRpcError(err, 'No se pudo agregar el premio')
    } finally {
      setBusy(false)
    }
  }

  async function removePrize(prize) {
    const ok = await confirmDanger({
      title: `¿Eliminar "${prize.title}"?`,
      text: 'Se quita el premio del evento.',
      confirmText: 'Eliminar',
    })
    if (!ok) return
    try {
      await callRpc('prize_delete', { p_prize_id: prize.id })
      qc.invalidateQueries({ queryKey: ['event-prizes-manage', event.id] })
    } catch (err) {
      showRpcError(err)
    }
  }

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <Badge tone={isDraft ? 'neutral' : 'available'}>
              {isDraft ? 'Borrador' : event.status}
            </Badge>
            <h3 className="font-semibold text-ink-900">{event.title}</h3>
          </div>
          <p className="mt-1 text-sm text-ink-500">
            Números {event.numbers_from}–{event.numbers_to}
            {event.price_per_number > 0 && (
              <span className="tnum"> · ${event.price_per_number} {event.currency}</span>
            )}
          </p>
        </div>
        {isDraft && <PublishButton event={event} />}
      </div>

      {isDraft && (
        <div className="mt-4 border-t border-ink-100 pt-4">
          <div className="mb-2 flex items-center justify-between">
            <p className="text-sm font-medium text-ink-700">Premios</p>
            <Button variant="ghost" size="sm" onClick={() => setAdding((a) => !a)}>
              {adding ? 'Cancelar' : '+ Agregar premio'}
            </Button>
          </div>

          {prizes?.length ? (
            <ul className="mb-3 space-y-1">
              {prizes.map((p) => (
                <li key={p.id} className="flex items-center justify-between rounded-md bg-ink-50 px-3 py-2 text-sm">
                  <span>{p.position}. {p.title}</span>
                  <button
                    type="button"
                    onClick={() => removePrize(p)}
                    className="text-xs text-error-500 hover:underline"
                  >
                    Quitar
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p className="mb-3 text-sm text-ink-400">Todavía no hay premios.</p>
          )}

          {adding && (
            <form onSubmit={addPrize} className="flex gap-2">
              <Input
                aria-label="Nombre del premio"
                value={prizeTitle}
                onChange={(e) => setPrizeTitle(e.target.value)}
                placeholder="Ej: Orden de compra $100.000"
                className="flex-1"
              />
              <Button type="submit" loading={busy} size="sm">
                Agregar
              </Button>
            </form>
          )}
        </div>
      )}
    </Card>
  )
}
