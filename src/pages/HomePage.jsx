import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { listPublicEvents } from '../services/supabase/queries/events.js'
import { LoadingState } from '../components/ui/LoadingState.jsx'
import { EmptyState } from '../components/ui/EmptyState.jsx'
import { Card } from '../components/ui/Card.jsx'
import { Badge } from '../components/ui/Badge.jsx'
import { Button } from '../components/ui/Button.jsx'
import { EVENT_STATUS } from '../constants/statuses.js'

function EventCard({ event }) {
  const open = [EVENT_STATUS.PUBLISHED, EVENT_STATUS.OPEN].includes(event.status)
  return (
    <Link to={`/e/${event.slug}`} className="block">
      <Card className="h-full transition-shadow hover:shadow-pop">
        <div className="flex h-full flex-col justify-between gap-3">
          <div>
            <div className="mb-2 flex items-center justify-between gap-2">
              <Badge tone={open ? 'available' : event.status === EVENT_STATUS.DRAWN ? 'winner' : 'neutral'}>
                {open ? 'Abierto' : event.status === EVENT_STATUS.DRAWN ? 'Finalizado' : 'Cerrado'}
              </Badge>
              {event.price_per_number > 0 && (
                <span className="tnum text-sm font-semibold text-ink-700">
                  ${event.price_per_number} <span className="font-normal text-ink-400">{event.currency}</span>
                </span>
              )}
            </div>
            <h3 className="font-semibold text-ink-900">{event.title}</h3>
            <p className="mt-1 text-sm text-ink-500">
              Números del {event.numbers_from} al {event.numbers_to}
            </p>
          </div>
          <p className="text-xs text-ink-400">
            Cierra: {new Date(event.participation_ends_at).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })}
          </p>
        </div>
      </Card>
    </Link>
  )
}

export function HomePage() {
  const { data: events, isLoading, error } = useQuery({
    queryKey: ['public-events'],
    queryFn: listPublicEvents,
  })

  return (
    <div className="space-y-10">
      <section className="rounded-lg bg-ink-950 px-6 py-14 text-center text-paper-100 sm:px-12">
        <h1 className="mx-auto max-w-2xl text-3xl font-bold leading-tight sm:text-4xl">
          Publicá tu sorteo y compartí el enlace. <span className="text-accent-300">Nosotros nos ocupamos del resto.</span>
        </h1>
        <p className="mx-auto mt-4 max-w-xl text-ink-300">
          Números, reservas, comprobantes y ganadores — todo en un solo lugar, auditable y sin depender de WhatsApp.
        </p>
        <div className="mt-7 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <Link to="/ingresar">
            <Button size="lg">Soy comerciante</Button>
          </Link>
          <Link to="/registrarse">
            <Button size="lg" variant="secondary">
              Quiero participar
            </Button>
          </Link>
        </div>
      </section>

      <section>
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-xl font-semibold text-ink-900">Sorteos activos</h2>
        </div>

        {isLoading ? (
          <LoadingState label="Buscando sorteos…" />
        ) : error ? (
          <EmptyState title="No pudimos cargar los sorteos" description="Probá de nuevo en un momento." />
        ) : !events?.length ? (
          <EmptyState
            title="Todavía no hay sorteos publicados"
            description="Cuando un comercio publique uno, aparece acá."
          />
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {events.map((event) => (
              <EventCard key={event.id} event={event} />
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
