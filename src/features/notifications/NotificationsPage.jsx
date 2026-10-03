import { useQueryClient } from '@tanstack/react-query'
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
  const { data, isLoading } = useNotifications()
  const list = data?.list ?? []
  const unread = data?.unread ?? 0

  async function markAll() {
    const ids = list.filter((n) => !n.read_at).map((n) => n.id)
    if (!ids.length) return
    try {
      await callRpc('notifications_mark_read', { p_ids: ids })
      qc.invalidateQueries({ queryKey: ['notifications'] })
      showSuccess('Todas marcadas como leídas')
    } catch (e) {
      showRpcError(e)
    }
  }

  async function markOne(n) {
    if (n.read_at) return
    try {
      await callRpc('notifications_mark_read', { p_ids: [n.id] })
      qc.invalidateQueries({ queryKey: ['notifications'] })
    } catch {
      // Silencioso: si falla, no pasa nada grave.
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-ink-900">Notificaciones</h1>
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
