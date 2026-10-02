import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { listMyReservations } from '../../services/supabase/queries/reservations.js'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'
import { Card } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { RESERVATION_STATUS, RESERVATION_STATUS_LABEL } from '../../constants/statuses.js'

const TONE = {
  [RESERVATION_STATUS.PENDING]: 'reserved',
  [RESERVATION_STATUS.PAYMENT_SUBMITTED]: 'submitted',
  [RESERVATION_STATUS.APPROVED]: 'paid',
  [RESERVATION_STATUS.EXPIRED]: 'neutral',
  [RESERVATION_STATUS.REJECTED]: 'error',
  [RESERVATION_STATUS.CANCELLED]: 'neutral',
}

export function MyParticipationsPage() {
  const { isAnonymous } = useAuth()
  const { data: reservations, isLoading } = useQuery({
    queryKey: ['my-reservations'],
    queryFn: listMyReservations,
  })

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-ink-900">Mis participaciones</h1>
          <p className="text-sm text-ink-500">Tus reservas, números y premios.</p>
        </div>
        {isAnonymous && (
          <Link to="/crear-cuenta">
            <Badge tone="accent">Crear cuenta</Badge>
          </Link>
        )}
      </div>

      {isAnonymous && (
        <Card className="border-accent-200 bg-accent-50">
          <p className="text-sm text-accent-900">
            Estás participando <strong>sin cuenta</strong>. Si creás una, podés ver tu historial desde cualquier
            dispositivo y no perdés nada. <Link to="/crear-cuenta" className="font-semibold underline">Crear cuenta</Link>
          </p>
        </Card>
      )}

      {isLoading ? (
        <LoadingState label="Buscando tus participaciones…" />
      ) : !reservations?.length ? (
        <EmptyState
          title="Todavía no participaste en ningún sorteo"
          description="Cuando reserves números, aparecen acá."
          action={
            <Link to="/">
              <Button>Ver sorteos</Button>
            </Link>
          }
        />
      ) : (
        <div className="space-y-3">
          {reservations.map((r) => (
            <Card key={r.id} className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="flex items-center gap-2">
                  <Badge tone={TONE[r.status] || 'neutral'}>{RESERVATION_STATUS_LABEL[r.status] || r.status}</Badge>
                  <span className="text-sm font-medium text-ink-900">{r.number_count} número(s)</span>
                </div>
                <p className="mt-1 text-sm text-ink-500">
                  {r.total_amount > 0 ? (
                    <span className="tnum font-medium text-ink-700">${r.total_amount} {r.currency}</span>
                  ) : (
                    'Gratis'
                  )}
                  {' · '}
                  {new Date(r.reserved_at).toLocaleDateString('es-AR', { dateStyle: 'medium' })}
                </p>
              </div>
              <Button variant="secondary" size="sm">Ver detalle</Button>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
