import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listMerchantEvents, listMyMerchants } from '../../services/supabase/queries/merchant.js'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { Card } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'
import { EventForm } from './EventForm.jsx'
import { EventManageCard } from './EventManageCard.jsx'
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
  const active = (events || []).filter((e) => e.status !== EVENT_STATUS.DRAFT)

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
        <div className="space-y-4">
          {drafts.length > 0 && (
            <div className="space-y-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-ink-400">En borrador</h3>
              {drafts.map((e) => (
                <EventManageCard key={e.id} event={e} />
              ))}
            </div>
          )}
          {active.length > 0 && (
            <div className="space-y-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-ink-400">Publicados</h3>
              {active.map((e) => (
                e.status === EVENT_STATUS.CLOSED ? (
                  <EventManageCard key={e.id} event={e} />
                ) : (
                  <Card key={e.id}>
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="font-semibold text-ink-900">{e.title}</p>
                        <p className="text-sm text-ink-500">Números {e.numbers_from}–{e.numbers_to} · {e.status}</p>
                      </div>
                    </div>
                  </Card>
                )
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
