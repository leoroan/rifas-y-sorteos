import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listMerchantEvents, listMyMerchants } from '../../services/supabase/queries/merchant.js'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'
import { EventForm } from './EventForm.jsx'
import { EventManageCard } from './EventManageCard.jsx'
import { ReceiptsCard } from '../payments/ReceiptsCard.jsx'
import { MerchantStats } from './MerchantStats.jsx'
import { EVENT_STATUS } from '../../constants/statuses.js'

export function PanelPage() {
  const { user } = useAuth()
  const [merchantId, setMerchantId] = useState('')
  const [showForm, setShowForm] = useState(false)

  const { data: memberships, isLoading: loadingMemberships } = useQuery({
    queryKey: ['my-merchants', user?.id],
    queryFn: listMyMerchants,
    enabled: !!user,
  })

  const selected = useMemo(
    () => merchantId || memberships?.[0]?.id || '',
    [merchantId, memberships],
  )

  const { data: events, isLoading: loadingEvents } = useQuery({
    queryKey: ['merchant-events', selected],
    queryFn: () => listMerchantEvents(selected),
    enabled: !!selected,
  })

  if (loadingMemberships) return <LoadingState label="Cargando tu comercio…" />

  if (!memberships?.length) {
    return (
      <EmptyState
        title="Todavía no administrás ningún comercio"
        description="Pedile al propietario de la plataforma que te asigne como comerciante o colaborador."
      />
    )
  }

  const drafts = (events || []).filter((e) => e.status === EVENT_STATUS.DRAFT)
  const inPlay = (events || []).filter((e) => [EVENT_STATUS.PUBLISHED, EVENT_STATUS.OPEN].includes(e.status))
  const finished = (events || []).filter((e) => [EVENT_STATUS.CLOSED, EVENT_STATUS.DRAWN].includes(e.status))
  const cancelled = (events || []).filter((e) => e.status === EVENT_STATUS.CANCELLED)

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-ink-900">Panel del comercio</h1>
          <p className="text-sm text-ink-500">Creá eventos, agregá premios y publicalos.</p>
        </div>
        {memberships.length > 1 && (
          <select
            value={selected}
            onChange={(e) => setMerchantId(e.target.value)}
            aria-label="Comercio"
            className="h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900"
          >
            {memberships.map((m) => (
              <option key={m.id} value={m.id}>{m.name}</option>
            ))}
          </select>
        )}
      </div>

      <MerchantStats merchantId={selected} />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <ReceiptsCard merchantId={selected} />
        <Card>
          <CardHeader title="Accesos rápidos" />
          <p className="text-sm text-ink-500">
            Desde acá vas a poder revisar reservas, compartir el sorteo y administrar a tu equipo.
            (Lo siguiente en la lista.)
          </p>
        </Card>
      </div>

      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-ink-900">Eventos</h2>
        <Button onClick={() => setShowForm((s) => !s)} variant={showForm ? 'secondary' : 'primary'}>
          {showForm ? 'Cancelar' : '+ Nuevo evento'}
        </Button>
      </div>

      {showForm && (
        <EventForm merchantId={selected} onCreated={() => setShowForm(false)} />
      )}

      {loadingEvents ? (
        <LoadingState />
      ) : !events?.length ? (
        <EmptyState
          title="Todavía no hay eventos"
          description="Creá el primero con el botón de arriba."
        />
      ) : (
        <div className="space-y-6">
          {drafts.length > 0 && (
            <section className="space-y-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-ink-400">En borrador</h3>
              {drafts.map((e) => (
                <EventManageCard key={e.id} event={e} />
              ))}
            </section>
          )}
          {inPlay.length > 0 && (
            <section className="space-y-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-ink-400">En juego</h3>
              {inPlay.map((e) => (
                <EventManageCard key={e.id} event={e} />
              ))}
            </section>
          )}
          {finished.length > 0 && (
            <section className="space-y-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-ink-400">Finalizados</h3>
              {finished.map((e) => (
                <EventManageCard key={e.id} event={e} />
              ))}
            </section>
          )}
          {cancelled.length > 0 && (
            <section className="space-y-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-ink-400">Cancelados</h3>
              {cancelled.map((e) => (
                <Card key={e.id}>
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-ink-900">{e.title}</p>
                      <p className="text-sm text-ink-500">Números {e.numbers_from}–{e.numbers_to} · Cancelado</p>
                    </div>
                  </div>
                </Card>
              ))}
            </section>
          )}
        </div>
      )}
    </div>
  )
}
