import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { listPublicEvents } from '../services/supabase/queries/events.js'
import { LoadingState } from '../components/ui/LoadingState.jsx'
import { EmptyState } from '../components/ui/EmptyState.jsx'
import { Card } from '../components/ui/Card.jsx'
import { Badge } from '../components/ui/Badge.jsx'
import { Button } from '../components/ui/Button.jsx'
import { EVENT_STATUS } from '../constants/statuses.js'

/*
 * La home es la primera impresión. Objetivo: que alguien que cae sin conocer
 * la app entienda en segundos qué es, confíe, y sepa qué hacer. El motivo
 * visual de los números es la identidad del producto: un sorteo se juega con
 * números.
 */

function NumberMotif() {
  const winner = 7
  return (
    <div className="relative">
      <div className="grid grid-cols-5 gap-2 rounded-2xl border border-ink-200 bg-paper-100 p-5 shadow-card">
        {Array.from({ length: 20 }, (_, i) => (
          <div
            key={i}
            className={`tnum grid h-11 place-items-center rounded-md border text-sm font-bold sm:h-12 ${
              i === winner
                ? 'border-winner-300 bg-winner-100 text-winner-700 ring-2 ring-winner-400'
                : 'border-ink-200 bg-ink-50 text-ink-500'
            }`}
          >
            {String(i + 1).padStart(2, '0')}
          </div>
        ))}
      </div>
      <div className="absolute -bottom-4 right-4 rounded-lg bg-paid-500 px-3 py-1.5 text-sm font-bold text-white shadow-pop">
        Ganador verificable
      </div>
    </div>
  )
}

function Hero() {
  return (
    <section className="overflow-hidden rounded-2xl bg-ink-950 text-paper-100">
      <div className="grid gap-10 px-6 py-12 sm:px-10 lg:grid-cols-2 lg:items-center lg:gap-8 lg:py-16">
        <div>
          <Badge tone="accent" className="mb-4">Plataforma de sorteos y rifas</Badge>
          <h1 className="text-3xl font-bold leading-tight tracking-tight sm:text-4xl lg:text-5xl">
            Sorteos claros, transparentes y verificables.
          </h1>
          <p className="mt-4 max-w-md text-base leading-relaxed text-ink-300">
            Publicá tu sorteo, compartí el enlace y olvidate del caos. Los participantes eligen números,
            suben el comprobante, y vos definís el ganador — con evidencia y auditoría completa.
          </p>
          <div className="mt-7 flex flex-col gap-3 sm:flex-row">
            <Link to="/ingresar">
              <Button size="lg" className="w-full sm:w-auto">Publicá tu sorteo</Button>
            </Link>
            <Link to="#sorteos" className="sm:w-auto">
              <Button size="lg" variant="secondary" className="w-full bg-paper-100/10 text-paper-100 hover:bg-paper-100/20 sm:w-auto">
                Explorar sorteos
              </Button>
            </Link>
          </div>
          <ul className="mt-8 flex flex-wrap gap-x-5 gap-y-2 text-sm text-ink-300">
            <li className="flex items-center gap-2"><Dot /> Seed público verificable</li>
            <li className="flex items-center gap-2"><Dot /> Comprobantes privados</li>
            <li className="flex items-center gap-2"><Dot /> Auditoría completa</li>
          </ul>
        </div>
        <div className="lg:justify-self-end">
          <NumberMotif />
        </div>
      </div>
    </section>
  )
}

function Dot() {
  return <span className="h-1.5 w-1.5 rounded-full bg-accent-400" aria-hidden="true" />
}

function TrustStrip() {
  const items = [
    { title: 'Verificable', desc: 'El seed y la fórmula del sorteo son públicos. Cualquiera puede recalcular el ganador.' },
    { title: 'Sin caos', desc: 'Números, reservas y comprobantes en un solo lugar. Sin capturas de pantalla ni planillas.' },
    { title: 'Privado por diseño', desc: 'Los comprobantes viven en un espacio privado, no en un grupo de WhatsApp.' },
    { title: 'Sin WhatsApp obligatorio', desc: 'Compartís el enlace donde quieras. La plataforma no depende de ningún chat.' },
  ]
  return (
    <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      {items.map((it) => (
        <Card key={it.title} padding="p-4">
          <p className="font-semibold text-ink-900">{it.title}</p>
          <p className="mt-1 text-sm leading-relaxed text-ink-500">{it.desc}</p>
        </Card>
      ))}
    </section>
  )
}

function Step({ n, title, desc }) {
  return (
    <div className="flex gap-3">
      <span className="tnum grid h-8 w-8 shrink-0 place-items-center rounded-full bg-accent-600 text-sm font-bold text-white">
        {n}
      </span>
      <div>
        <p className="font-semibold text-ink-900">{title}</p>
        <p className="text-sm leading-relaxed text-ink-500">{desc}</p>
      </div>
    </div>
  )
}

function HowItWorks() {
  return (
    <section className="grid gap-8 rounded-2xl border border-ink-200 bg-paper-100 p-6 sm:p-8 lg:grid-cols-2">
      <div>
        <h2 className="text-lg font-bold text-ink-900">Si sos comerciante</h2>
        <div className="mt-4 flex flex-col gap-4">
          <Step n={1} title="Creás el sorteo" desc="Números, precio, premios y cómo se elige el ganador. Lo publicás con un clic." />
          <Step n={2} title="Compartís el enlace" desc="Copiás el texto listo para WhatsApp, Telegram o donde quieras. Sin integraciones raras." />
          <Step n={3} title="Confirmás y sorteás" desc="Aprobás los comprobantes y cargás el resultado. Los ganadores se publican solos." />
        </div>
      </div>
      <div>
        <h2 className="text-lg font-bold text-ink-900">Si querés participar</h2>
        <div className="mt-4 flex flex-col gap-4">
          <Step n={1} title="Elegís tus números" desc="Abrir el enlace, ver el sorteo, elegir. Sin crear cuenta si no querés." />
          <Step n={2} title="Subís el comprobante" desc="Pagás por fuera y subís la foto. El comercio lo valida." />
          <Step n={3} title="Seguís el resultado" desc="Te avisamos si ganás. Podés verificar el sorteo vos mismo." />
        </div>
      </div>
    </section>
  )
}

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
            <p className="mt-1 text-sm text-ink-500">Números del {event.numbers_from} al {event.numbers_to}</p>
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
  const { data: allEvents, isLoading, error } = useQuery({
    queryKey: ['public-events'],
    queryFn: listPublicEvents,
  })

  // Activos = abiertos Y dentro de la ventana. El estado describe, el reloj manda.
  const now = new Date()
  const isOpen = (e) =>
    [EVENT_STATUS.PUBLISHED, EVENT_STATUS.OPEN].includes(e.status) &&
    new Date(e.participation_ends_at) > now
  const active = (allEvents || []).filter(isOpen)
  const finished = (allEvents || []).filter((e) => e.status === EVENT_STATUS.DRAWN)

  return (
    <div className="space-y-10">
      <Hero />
      <TrustStrip />
      <HowItWorks />

      <section id="sorteos">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-xl font-semibold text-ink-900">Sorteos activos</h2>
        </div>
        {isLoading ? (
          <LoadingState label="Buscando sorteos…" />
        ) : error ? (
          <EmptyState title="No pudimos cargar los sorteos" description="Probá de nuevo en un momento." />
        ) : !active.length ? (
          <EmptyState
            title="No hay sorteos activos ahora"
            description="Cuando un comercio publique uno, aparece acá."
            action={
              <Link to="/ingresar">
                <Button>Publicá el primero</Button>
              </Link>
            }
          />
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {active.map((event) => (
              <EventCard key={event.id} event={event} />
            ))}
          </div>
        )}

        {finished.length > 0 && (
          <div className="mt-10">
            <h2 className="mb-4 text-xl font-semibold text-ink-900">Finalizados</h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {finished.map((event) => (
                <EventCard key={event.id} event={event} />
              ))}
            </div>
          </div>
        )}
      </section>
    </div>
  )
}
