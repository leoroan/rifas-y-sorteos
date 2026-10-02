import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../services/supabase/client.js'
import { Link, useParams } from 'react-router-dom'
import { getEventMerchant, getEventNumbersSummary, getEventPrizes, getPublicEventBySlug } from '../../services/supabase/queries/events.js'
import { FullPageLoader } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'

import { ReservePanel } from '../reservations/ReservePanel.jsx'
import { EVENT_STATUS } from '../../constants/statuses.js'

const STATUS_TONE = {
  [EVENT_STATUS.PUBLISHED]: 'available',
  [EVENT_STATUS.OPEN]: 'available',
  [EVENT_STATUS.CLOSED]: 'neutral',
  [EVENT_STATUS.DRAWN]: 'winner',
  [EVENT_STATUS.CANCELLED]: 'error',
}

function Stat({ label, value }) {
  return (
    <div className="rounded-md bg-ink-50 px-3 py-2 text-center">
      <div className="tnum text-lg font-bold text-ink-900">{value}</div>
      <div className="text-xs text-ink-500">{label}</div>
    </div>
  )
}

export function EventPage({ resultado: _resultado = false }) {
  const { slug } = useParams()

  const { data: event, isLoading, error } = useQuery({
    queryKey: ['event', slug],
    queryFn: () => getPublicEventBySlug(slug),
    enabled: !!slug,
  })

  const { data: prizes } = useQuery({
    queryKey: ['event-prizes', event?.id],
    queryFn: () => getEventPrizes(event.id),
    enabled: !!event?.id,
  })

  const { data: summary } = useQuery({
    queryKey: ['event-summary', event?.id],
    queryFn: () => getEventNumbersSummary(event.id),
    enabled: !!event?.id,
  })

  const { data: merchant } = useQuery({
    queryKey: ['event-merchant', event?.id],
    queryFn: () => getEventMerchant(event.id),
    enabled: !!event?.id,
  })

  if (isLoading) return <FullPageLoader label="Cargando el sorteo…" />
  if (error || !event) {
    return (
      <EmptyState
        title="No encontramos ese sorteo"
        description="Puede que haya sido cancelado o que el enlace esté mal."
        action={
          <Link to="/">
            <Button variant="secondary">Ver todos los sorteos</Button>
          </Link>
        }
      />
    )
  }

  const open = [EVENT_STATUS.PUBLISHED, EVENT_STATUS.OPEN].includes(event.status)
  const drawn = event.status === EVENT_STATUS.DRAWN

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="mb-2 flex items-center gap-2">
            <Badge tone={STATUS_TONE[event.status] || 'neutral'}>
              {open ? 'Abierto' : drawn ? 'Finalizado' : event.status === EVENT_STATUS.CANCELLED ? 'Cancelado' : 'Cerrado'}
            </Badge>
            {merchant && <span className="text-sm text-ink-500">{merchant.name}</span>}
          </div>
          <h1 className="text-2xl font-bold text-ink-900">{event.title}</h1>
          {event.description && <p className="mt-1 text-ink-600">{event.description}</p>}
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <Stat label="Por número" value={event.price_per_number > 0 ? `$${event.price_per_number}` : 'Gratis'} />
        <Stat label="Quedan" value={summary ? `${summary.available}/${summary.total}` : '…'} />
        <Stat label="Total" value={event.numbers_to - event.numbers_from + 1} />
      </div>

      {summary && summary.total > 0 && (
        <div className="h-2 w-full overflow-hidden rounded-full bg-ink-100">
          <div
            className="h-full rounded-full bg-accent-500 transition-all"
            style={{ width: `${Math.max(2, Math.round((summary.available / summary.total) * 100))}%` }}
            aria-label={`Quedan ${summary.available} de ${summary.total}`}
          />
        </div>
      )}

      {prizes?.length > 0 && (
        <Card>
          <CardHeader title="Premios" />
          <ul className="divide-y divide-ink-100">
            {prizes.map((prize) => (
              <li key={prize.id} className="flex items-center justify-between gap-3 py-3">
                <div>
                  <p className="font-medium text-ink-900">{prize.title}</p>
                  {prize.description && <p className="text-sm text-ink-500">{prize.description}</p>}
                </div>
                {prize.estimated_value != null && (
                  <span className="tnum shrink-0 text-sm font-semibold text-ink-700">
                    ${prize.estimated_value}
                  </span>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card>
        <CardHeader title="Cómo se determina el ganador" />
        <p className="text-sm text-ink-600">
          {event.winner_method === 'RANDOM_SEEDED'
            ? 'Sorteo aleatorio del sistema, con seed público y verificable.'
            : event.winner_method === 'MANUAL'
              ? 'Lo define el comercio, con justificación y evidencia publicadas.'
              : 'Por una lotería de referencia.'}
        </p>
      </Card>

      {open && <ReservePanel event={event} merchant={merchant} />}

      {drawn && <WinnersCard event={event} />}

      {!open && !drawn && (
        <EmptyState
          title={event.status === EVENT_STATUS.CANCELLED ? 'Este sorteo fue cancelado' : 'La participación está cerrada'}
          description={event.status === EVENT_STATUS.CANCELLED ? event.cancellation_reason : 'Ya no se aceptan más números.'}
        />
      )}
    </div>
  )
}


function WinnersCard({ event }) {
  const { data: winners } = useQuery({
    queryKey: ['event-winners', event.id],
    queryFn: async () => {
      const [w, prizes] = await Promise.all([
        supabase
          .from('public_event_winners')
          .select('*')
          .eq('event_id', event.id)
          .order('position', { ascending: true })
          .then(({ data, error }) => { if (error) throw error; return data }),
        supabase
          .from('public_prizes')
          .select('id, title')
          .eq('event_id', event.id)
          .then(({ data, error }) => { if (error) throw error; return data }),
      ])
      const byPrize = Object.fromEntries((prizes || []).map((p) => [p.id, p.title]))
      return (w || []).map((x) => ({ ...x, prize_title: byPrize[x.prize_id] ?? 'Premio' }))
    },
  })

  const { data: drawResult } = useQuery({
    queryKey: ['draw-result', event.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('draw_results')
        .select('winner_method_snapshot, algorithm, seed, computed_number, justification, evidence_url, recorded_at')
        .eq('event_id', event.id)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })

  return (
    <Card>
      <CardHeader title="Ganadores" subtitle={`Sorteo finalizado`} />
      {winners?.length ? (
        <ul className="divide-y divide-ink-100">
          {winners.map((w) => (
            <li key={w.position} className="flex items-center justify-between gap-3 py-3">
              <div>
                <p className="font-medium text-ink-900">{w.prize_title}</p>
                <p className="text-sm text-ink-500">{w.winner_display ?? 'Participante'}</p>
              </div>
              <span className="tnum rounded-md border border-winner-300 bg-winner-50 px-3 py-1 font-bold text-winner-700">
                {w.number}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-ink-500">Cargando ganadores…</p>
      )}

      {drawResult?.seed && (
        <div className="mt-4 rounded-md bg-ink-50 p-3 text-xs text-ink-600">
          <p className="mb-1 font-medium text-ink-800">Verificá el sorteo</p>
          <p className="break-all">Seed: {drawResult.seed}</p>
          <p className="mt-1">Algoritmo: {drawResult.algorithm}</p>
        </div>
      )}
    </Card>
  )
}
