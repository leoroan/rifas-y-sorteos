import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getEventNumbers } from '../../services/supabase/queries/events.js'
import { NUMBER_STATUS, NUMBER_STATUS_LABEL } from '../../constants/statuses.js'
import { LoadingState } from '../ui/LoadingState.jsx'

const PAGE = 300

const tone = {
  [NUMBER_STATUS.AVAILABLE]: 'border-ink-200 bg-paper-100 text-ink-600',
  [NUMBER_STATUS.RESERVED]: 'border-reserved-200 bg-reserved-50 text-reserved-700',
  [NUMBER_STATUS.PAYMENT_SUBMITTED]: 'border-submitted-200 bg-submitted-50 text-submitted-700',
  [NUMBER_STATUS.PAID]: 'border-paid-200 bg-paid-50 text-paid-700',
  [NUMBER_STATUS.CANCELLED]: 'border-ink-100 bg-ink-50 text-ink-300',
  [NUMBER_STATUS.WINNER]: 'border-winner-300 bg-winner-100 text-winner-700 font-bold ring-2 ring-winner-400',
}

/*
 * Grilla de números de sólo lectura: para eventos vencidos, cerrados o
 * sorteados. Muestra el estado final (con el ganador destacado) sin ofrecer
 * interacción. El participante no "reserva" acá: consulta.
 */
export function NumbersGrid({ event, title = 'Números del sorteo' }) {
  const [page, setPage] = useState(1)
  const { data: numbers, isLoading } = useQuery({
    queryKey: ['event-numbers', event.id],
    queryFn: () => getEventNumbers(event.id),
  })

  if (isLoading) return <LoadingState />

  const list = numbers || []
  const visible = list.slice(0, page * PAGE)

  return (
    <div>
      <p className="mb-3 text-sm font-medium text-ink-700">{title}</p>
      <div className="grid grid-cols-[repeat(auto-fill,minmax(3.25rem,1fr))] gap-1.5">
        {visible.map((n) => (
          <div
            key={n.number}
            title={NUMBER_STATUS_LABEL[n.status] ?? n.status}
            className={`tnum grid h-10 place-items-center rounded-md border text-sm font-semibold ${tone[n.status] ?? 'border-ink-200 bg-paper-100 text-ink-600'}`}
          >
            {n.display_code ?? n.number}
          </div>
        ))}
      </div>
      {list.length > visible.length && (
        <button
          type="button"
          onClick={() => setPage((p) => p + 1)}
          className="mt-3 text-sm font-medium text-accent-600 hover:underline"
        >
          Mostrar más ({list.length - visible.length} restantes)
        </button>
      )}
    </div>
  )
}
