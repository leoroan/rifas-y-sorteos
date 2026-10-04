import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listMerchants } from '../../services/supabase/queries/admin.js'
import { getMerchantActivity } from '../../services/supabase/queries/merchantActivity.js'
import { Card } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'

const STATUS_LABEL = { ACTIVE: 'Activo', SUSPENDED: 'Suspendido', CLOSED: 'Cerrado' }
const STATUS_TONE = { ACTIVE: 'available', SUSPENDED: 'warn', CLOSED: 'neutral' }
const EVENT_STATUS_ES = {
  DRAFT: 'Borrador', PUBLISHED: 'Publicado', OPEN: 'Abierto',
  CLOSED: 'Cerrado', DRAWN: 'Sorteado', CANCELLED: 'Cancelado',
}

function Stat({ label, value, tone }) {
  return (
    <div className="rounded-md bg-ink-50 px-3 py-2 text-center">
      <div className={`tnum text-lg font-bold ${tone || 'text-ink-900'}`}>{value}</div>
      <div className="text-xs text-ink-500">{label}</div>
    </div>
  )
}

function ActivityDetail({ merchantId }) {
  const { data: act, isLoading } = useQuery({
    queryKey: ['merchant-activity', merchantId],
    queryFn: () => getMerchantActivity(merchantId),
  })

  if (isLoading) return <LoadingState />
  if (!act) return null

  if (!act.hasActivity) {
    return <p className="mt-2 text-sm text-ink-400">Este comercio todavia no uso el sistema.</p>
  }

  return (
    <div className="mt-4 space-y-4 border-t border-ink-100 pt-4">
      <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
        <Stat label="Eventos" value={act.totalEvents} />
        <Stat label="Participantes" value={act.uniqueParticipants} />
        <Stat label="Numeros vendidos" value={act.totalNumbersSold} />
        <Stat label="Recaudacion" value={'$' + act.totalRevenue.toLocaleString('es-AR')} tone="text-accent-700" />
        <Stat label="Aprobados" value={act.receiptsApproved} tone="text-paid-700" />
        <Stat label="Rechazados" value={act.receiptsRejected} tone="text-error-500" />
      </div>

      {act.lastSeen && (
        <p className="text-xs text-ink-400">
          Ultimo acceso del equipo: {new Date(act.lastSeen).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })}
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        {Object.entries(act.eventsByStatus).map(([st, n]) => (
          <Badge key={st} tone="neutral">{EVENT_STATUS_ES[st] || st}: {n}</Badge>
        ))}
      </div>

      {act.totalEvents > 0 && (
        <div>
          <p className="mb-2 text-sm font-medium text-ink-700">Eventos con recaudacion</p>
          <ul className="divide-y divide-ink-100">
            {act.events.map((e) => {
              const rev = act.revenueByEvent[e.id]
              return (
                <li key={e.id} className="flex items-center justify-between gap-3 py-2 text-sm">
                  <div className="min-w-0">
                    <p className="truncate font-medium text-ink-800">{e.title}</p>
                    <p className="text-xs text-ink-400">
                      {EVENT_STATUS_ES[e.status] || e.status} | {e.numbers_from}-{e.numbers_to} | ${e.price_per_number}
                    </p>
                  </div>
                  {rev ? (
                    <span className="tnum shrink-0 font-semibold text-accent-700">
                      ${rev.total.toLocaleString('es-AR')} ({rev.count} num.)
                    </span>
                  ) : (
                    <span className="shrink-0 text-ink-300">Sin ventas</span>
                  )}
                </li>
              )
            })}
          </ul>
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        {Object.entries(act.resByStatus).map(([st, n]) => (
          <Badge key={st} tone="neutral">{st}: {n}</Badge>
        ))}
      </div>
    </div>
  )
}

function MerchantRow({ m }) {
  const [expanded, setExpanded] = useState(false)
  return (
    <div className="border-t border-ink-100 py-3 first:border-0">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="font-semibold text-ink-900">{m.name}</p>
            <Badge tone={STATUS_TONE[m.status] || 'neutral'}>{STATUS_LABEL[m.status] || m.status}</Badge>
            <Badge tone="accent">{m.plan_code || 'FREE'}</Badge>
          </div>
          <p className="text-sm text-ink-500">
            /{m.slug}
            {m.tax_type ? ' | ' + m.tax_type + ': ' + m.tax_id : ''}
            {m.tax_id && !m.tax_type ? ' | ' + m.tax_id : ''}
          </p>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setExpanded((e) => !e)}
        >
          {expanded ? 'Ocultar' : 'Actividad'}
        </Button>
      </div>
      {expanded && <ActivityDetail merchantId={m.id} />}
    </div>
  )
}

/*
 * Seccion Comercios: lista con filtro por estado + actividad completa.
 */
export function ComerciosSection() {
  const [filter, setFilter] = useState('ALL')
  const [search, setSearch] = useState('')

  const { data: merchants, isLoading } = useQuery({
    queryKey: ['merchants'],
    queryFn: listMerchants,
  })

  const filtered = useMemo(() => {
    let list = merchants || []
    if (filter !== 'ALL') list = list.filter((m) => m.status === filter)
    if (search.trim()) {
      const q = search.toLowerCase()
      list = list.filter((m) => m.name.toLowerCase().includes(q) || (m.slug || '').includes(q))
    }
    return list
  }, [merchants, filter, search])

  const counts = useMemo(() => {
    const list = merchants || []
    return {
      ALL: list.length,
      ACTIVE: list.filter((m) => m.status === 'ACTIVE').length,
      SUSPENDED: list.filter((m) => m.status === 'SUSPENDED').length,
      CLOSED: list.filter((m) => m.status === 'CLOSED').length,
    }
  }, [merchants])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Buscar por nombre o slug..."
          className="h-10 flex-1 rounded-md border border-ink-300 bg-paper-100 px-3 text-sm sm:max-w-xs"
        />
        <div className="flex flex-wrap gap-1">
          {['ALL', 'ACTIVE', 'SUSPENDED', 'CLOSED'].map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`rounded-md px-3 py-1.5 text-xs font-medium ${
                filter === f ? 'bg-accent-50 text-accent-700' : 'text-ink-400 hover:text-ink-700'
              }`}
            >
              {f === 'ALL' ? 'Todos' : STATUS_LABEL[f]} ({counts[f] || 0})
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <LoadingState />
      ) : !filtered.length ? (
        <Card><p className="py-6 text-center text-sm text-ink-400">No hay comercios con ese filtro.</p></Card>
      ) : (
        <Card>
          {filtered.map((m) => (
            <MerchantRow key={m.id} m={m} />
          ))}
        </Card>
      )}
    </div>
  )
}
