import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { useNotifications } from './useNotifications.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'
import { Card } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'

const TYPE_LABEL = {
  'reservation.created': 'Reserva',
  'reservation.expired': 'Reserva',
  'reservation.cancelled': 'Reserva',
  'payment.receipt.submitted': 'Pago',
  'payment.receipt.approved': 'Pago',
  'payment.receipt.rejected': 'Pago',
  'payment.correction_requested': 'Pago',
  'event.cancelled': 'Evento',
  'event.closed': 'Evento',
  'winner.confirmed': 'Premio',
  'account.converted': 'Cuenta',
  'staff.added': 'Equipo',
}

function timeAgo(iso) {
  const diff = Date.now() - new Date(iso).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return 'ahora'
  if (m < 60) return `hace ${m} min`
  const h = Math.floor(m / 60)
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  return d === 1 ? 'ayer' : `hace ${d} días`
}

export function NotificationsPage() {
  const qc = useQueryClient()
  const { user } = useAuth()
  const { data, isLoading } = useNotifications()
  const [error, setError] = useState(null)
  const list = data?.list ?? []
  const unread = data?.unread ?? 0

  // Optimista: actualiza el cache al toque, sin esperar la refetch.
  function optimistic(ids) {
    qc.setQueryData(['notifications', user?.id], (old) => {
      if (!old) return old
      const nowIso = new Date().toISOString()
      const list2 = (old.list || []).map((n) =>
        ids.includes(n.id) ? { ...n, read_at: nowIso, status: 'READ' } : n,
      )
      return { list: list2, unread: list2.filter((n) => !n.read_at).length }
    })
  }

  async function markAll() {
    setError(null)
    const ids = list.filter((n) => !n.read_at).map((n) => n.id)
    if (!ids.length) return
    optimistic(ids)
    try {
      await callRpc('notifications_mark_read', { p_ids: ids })
      qc.invalidateQueries({ queryKey: ['notifications'] })
      showSuccess('Todas marcadas como leídas')
    } catch (e) {
      qc.invalidateQueries({ queryKey: ['notifications'] })
      setError(e?.message || 'No se pudo marcar como leída.')
      showRpcError(e)
    }
  }

  async function markOne(n) {
    if (n.read_at) return
    setError(null)
    optimistic([n.id])
    try {
      await callRpc('notifications_mark_read', { p_ids: [n.id] })
      qc.invalidateQueries({ queryKey: ['notifications'] })
    } catch (e) {
      qc.invalidateQueries({ queryKey: ['notifications'] })
      setError(e?.message || 'No se pudo marcar como leída.')
      showRpcError(e)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-ink-900">Notificaciones</h1>
          {error && <p className="mt-1 text-sm text-error-500" role="alert">{error}</p>}
          <p className="text-sm text-ink-500">
            {unread > 0 ? `${unread} sin leer` : 'Estás al día.'}
          </p>
        </div>
        {unread > 0 && (
          <Button variant="secondary" size="sm" onClick={markAll}>
            Marcar todas como leídas
          </Button>
        )}
      </div>

      {isLoading ? (
        <LoadingState />
      ) : !list.length ? (
        <EmptyState
          title="Sin notificaciones todavía"
          description="Cuando algo pase con tus reservas, comprobantes o premios, aparece acá."
        />
      ) : (
        <ul className="space-y-2">
          {list.map((n) => (
            <li key={n.id}>
              <button
                type="button"
                onClick={() => markOne(n)}
                className={`block w-full text-left transition-shadow hover:shadow-pop ${
                  !n.read_at ? 'ring-1 ring-accent-200' : ''
                }`}
              >
                <Card padding="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex items-start gap-3">
                      <Badge tone={!n.read_at ? 'accent' : 'neutral'}>
                        {TYPE_LABEL[n.type] ?? 'Aviso'}
                      </Badge>
                      <div>
                        <p className={`text-sm ${!n.read_at ? 'font-semibold text-ink-900' : 'font-medium text-ink-700'}`}>
                          {n.title}
                        </p>
                        {n.body && <p className="mt-0.5 text-sm text-ink-500">{n.body}</p>}
                      </div>
                    </div>
                    <span className="shrink-0 text-xs text-ink-400">{timeAgo(n.created_at)}</span>
                  </div>
                </Card>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
