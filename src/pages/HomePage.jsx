import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { listPublicEvents } from '../services/supabase/queries/events.js'
import { site } from '../app/config/site.js'
import { LoadingState } from '../components/ui/LoadingState.jsx'
import { EmptyState } from '../components/ui/EmptyState.jsx'
import { Card } from '../components/ui/Card.jsx'
import { Badge } from '../components/ui/Badge.jsx'
import { Button } from '../components/ui/Button.jsx'
import { Icon } from '../components/ui/Icon.jsx'
import { EVENT_STATUS } from '../constants/statuses.js'

function Mark() {
  return (
    <div className="flex items-center gap-2.5">
      <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-600 text-lg font-bold text-white shadow-hero">
        {site.mark}
      </span>
      <span className="text-lg font-bold tracking-tight text-ink-900">{site.name}</span>
    </div>
  )
}

function NumberMotif() {
  const winner = 12
  const reserved = [3, 4, 9]
  const paid = [6, 15]
  return (
    <div className="relative">
      <div className="grid grid-cols-5 gap-2 rounded-2xl border border-ink-200 bg-paper-100 p-5 shadow-card">
        {Array.from({ length: 20 }, (_, i) => {
          const n = i + 1
          let cls = 'border-ink-200 bg-ink-50 text-ink-400'
          if (n === winner) cls = 'border-winner-400 bg-winner-100 text-winner-700 ring-2 ring-winner-400'
          else if (paid.includes(n)) cls = 'border-paid-200 bg-paid-50 text-paid-700'
          else if (reserved.includes(n)) cls = 'border-reserved-200 bg-reserved-50 text-reserved-700'
          return (
            <div key={n} className={`tnum grid h-10 place-items-center rounded-lg border text-sm font-bold sm:h-12 ${cls}`}>
              {String(n).padStart(2, '0')}
            </div>
          )
        })}
      </div>
      <div className="absolute -bottom-4 right-4 flex items-center gap-1.5 rounded-lg bg-paid-500 px-3 py-1.5 text-sm font-bold text-white shadow-pop">
        <Icon name="check" size={15} /> Verificable
      </div>
    </div>
  )
}

function Hero() {
  return (
    <section className="overflow-hidden rounded-2xl bg-ink-950 text-paper-100">
      <div className="grid gap-10 px-6 py-10 sm:px-10 lg:grid-cols-2 lg:items-center lg:gap-8 lg:py-16">
        <div>
          <Badge tone="accent" className="mb-4">Plataforma de sorteos y rifas</Badge>
          <h1 className="text-3xl font-bold leading-tight tracking-tight sm:text-4xl lg:text-[2.75rem] lg:leading-[1.1]">
            {site.tagline}
          </h1>
          <p className="mt-4 max-w-md text-base leading-relaxed text-ink-300">
            {site.description}
          </p>
          <div className="mt-7 flex flex-col gap-3 sm:flex-row">
            <Link to="/solicitar">
              <Button size="lg" className="w-full sm:w-auto">
                {site.heroCta} <Icon name="arrowRight" size={18} />
              </Button>
            </Link>
            <a href="#sorteos">
              <Button size="lg" variant="secondary" className="w-full bg-paper-100/10 text-paper-100 hover:bg-paper-100/20 sm:w-auto">
                {site.heroSecondary}
              </Button>
            </a>
          </div>
          <ul className="mt-8 flex flex-wrap gap-x-5 gap-y-2 text-sm text-ink-300">
            <li className="flex items-center gap-2"><Icon name="verified" size={16} className="text-brand-400" /> Seed público verificable</li>
            <li className="flex items-center gap-2"><Icon name="lock" size={16} className="text-brand-400" /> Comprobantes privados</li>
            <li className="flex items-center gap-2"><Icon name="receipt" size={16} className="text-brand-400" /> Auditoría completa</li>
          </ul>
        </div>
        <div className="lg:justify-self-end">
          <NumberMotif />
        </div>
      </div>
    </section>
  )
}

function TrustStrip() {
  const items = [
    { icon: 'verified', title: 'Verificable', desc: 'El seed y la fórmula del sorteo son públicos. Cualquiera puede recalcular el ganador.' },
    { icon: 'zap', title: 'Sin caos', desc: 'Números, reservas y comprobantes en un solo lugar. Sin capturas ni planillas.' },
    { icon: 'lock', title: 'Privado por diseño', desc: 'Los comprobantes viven en un espacio privado, no en un grupo de chat.' },
    { icon: 'link', title: 'Sin WhatsApp obligatorio', desc: 'Compartís el enlace donde quieras. La plataforma no depende de ningún chat.' },
  ]
  return (
    <section className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      {items.map((it) => (
        <Card key={it.title} padding="p-4">
          <div className="mb-2 grid h-9 w-9 place-items-center rounded-lg bg-brand-50 text-brand-600">
            <Icon name={it.icon} size={18} />
          </div>
          <p className="font-semibold text-ink-900">{it.title}</p>
          <p className="mt-1 text-sm leading-relaxed text-ink-500">{it.desc}</p>
        </Card>
      ))}
    </section>
  )
}

function Step({ n, icon, title, desc }) {
  return (
    <div className="flex gap-3">
      <span className="tnum grid h-8 w-8 shrink-0 place-items-center rounded-full bg-brand-600 text-sm font-bold text-white">
        {n}
      </span>
      <div>
        <p className="flex items-center gap-2 font-semibold text-ink-900">
          <Icon name={icon} size={16} className="text-brand-600" /> {title}
        </p>
        <p className="mt-0.5 text-sm leading-relaxed text-ink-500">{desc}</p>
      </div>
    </div>
  )
}

function HowItWorks() {
  return (
    <section className="grid gap-8 rounded-2xl border border-ink-200 bg-paper-100 p-6 sm:p-8 lg:grid-cols-2">
      <div>
        <h2 className="flex items-center gap-2 text-lg font-bold text-ink-900">
          <Icon name="store" size={20} className="text-brand-600" /> Si querés publicar sorteos
        </h2>
        <div className="mt-4 flex flex-col gap-4">
          <Step n={1} icon="edit" title="Creás el sorteo" desc="Números, precio, premios y cómo se elige el ganador. Lo publicás con un clic." />
          <Step n={2} icon="share" title="Compartís el enlace" desc="Copiás el texto listo para el canal que quieras. Sin integraciones raras." />
          <Step n={3} icon="check" title="Confirmás y sorteás" desc="Aprobás los comprobantes y cargás el resultado. Los ganadores se publican solos." />
        </div>
      </div>
      <div>
        <h2 className="flex items-center gap-2 text-lg font-bold text-ink-900">
          <Icon name="ticket" size={20} className="text-brand-600" /> Si querés participar
        </h2>
        <div className="mt-4 flex flex-col gap-4">
          <Step n={1} icon="ticket" title="Elegís tus números" desc="Abrir el enlace, ver el sorteo, elegir. Sin vueltas." />
          <Step n={2} icon="upload" title="Subís el comprobante" desc="Pagás por fuera y subís la foto. Se valida y queda registrado." />
          <Step n={3} icon="trophy" title="Seguís el resultado" desc="Te avisamos si ganás. Podés verificar el sorteo vos mismo." />
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
          <p className="flex items-center gap-1.5 text-xs text-ink-400">
            <Icon name="clock" size={13} />
            Cierra: {new Date(event.participation_ends_at).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })}
          </p>
        </div>
      </Card>
    </Link>
  )
}

function EventsGrid() {
  const { data: allEvents, isLoading, error } = useQuery({
    queryKey: ['public-events'],
    queryFn: listPublicEvents,
  })

  const now = new Date()
  const isOpen = (e) =>
    [EVENT_STATUS.PUBLISHED, EVENT_STATUS.OPEN].includes(e.status) &&
    new Date(e.participation_ends_at) > now
  const active = (allEvents || []).filter(isOpen)
  const finished = (allEvents || []).filter((e) => e.status === EVENT_STATUS.DRAWN)

  return (
    <section id="sorteos">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-xl font-bold text-ink-900">Sorteos activos</h2>
      </div>
      {isLoading ? (
        <LoadingState label="Buscando sorteos…" />
      ) : error ? (
        <EmptyState title="No pudimos cargar los sorteos" description="Probá de nuevo en un momento." />
      ) : !active.length ? (
        <EmptyState
          title="No hay sorteos activos ahora"
          description="Cuando alguien publique uno, aparece acá."
          action={<Link to="/solicitar"><Button>{site.heroCta}</Button></Link>}
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
          <h2 className="mb-4 text-xl font-bold text-ink-900">Finalizados</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {finished.map((event) => (
              <EventCard key={event.id} event={event} />
            ))}
          </div>
        </div>
      )}
    </section>
  )
}

function Footer() {
  return (
    <footer className="mt-14 border-t border-ink-200 pt-10">
      <div className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
        <div className="lg:col-span-2">
          <Mark />
          <p className="mt-3 max-w-sm text-sm text-ink-500">{site.footer.tagline}</p>
          <p className="mt-1 text-xs text-ink-400">{site.footer.note}</p>
        </div>
        <div>
          <p className="text-sm font-semibold text-ink-900">Legal</p>
          <ul className="mt-3 space-y-2 text-sm text-ink-500">
            <li><Link to="/terminos" className="hover:text-brand-600">Términos y condiciones</Link></li>
            <li><Link to="/privacidad" className="hover:text-brand-600">Política de privacidad</Link></li>
            <li><Link to="/reglas" className="hover:text-brand-600">Reglas de participación</Link></li>
          </ul>
        </div>
        <div>
          <p className="text-sm font-semibold text-ink-900">Producto</p>
          <ul className="mt-3 space-y-2 text-sm text-ink-500">
            <li><a href="#sorteos" className="hover:text-brand-600">Sorteos activos</a></li>
            <li><Link to="/solicitar" className="hover:text-brand-600">{site.heroCta}</Link></li>
            <li><Link to="/ingresar" className="hover:text-brand-600">Ingresar</Link></li>
          </ul>
        </div>
      </div>
      <div className="mt-10 flex flex-col items-center justify-between gap-2 border-t border-ink-200 py-5 text-xs text-ink-400 sm:flex-row">
        <span>© {new Date().getFullYear()} {site.name}</span>
        <span>Hecho con números y transparencia.</span>
      </div>
    </footer>
  )
}

export function HomePage() {
  return (
    <div>
      <Hero />
      <div className="mt-8 space-y-10">
        <TrustStrip />
        <HowItWorks />
        <EventsGrid />
      </div>
      <Footer />
    </div>
  )
}
