import { Link, NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../providers/AuthProvider.jsx'
import { env } from '../config/env.js'
import { Button } from '../../components/ui/Button.jsx'
import { Badge } from '../../components/ui/Badge.jsx'

function Icon({ d, className = 'h-5 w-5' }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden="true">
      <path d={d} />
    </svg>
  )
}

const ICONS = {
  home: 'M3 10.5 12 3l9 7.5V21a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1V10.5Z',
  ticket: 'M4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2a2 2 0 1 0 0 4v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2a2 2 0 1 0 0-4V8Z',
  store: 'M3 9l1.5-5h15L21 9M4 9h16v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V9Zm4 12v-6h8v6',
  shield: 'M12 3l8 3v6c0 4.5-3 8-8 9-5-1-8-4.5-8-9V6l8-3Z',
}

const NAVS = [
  { to: '/', label: 'Inicio', icon: ICONS.home, end: true, show: () => true },
  { to: '/mis-participaciones', label: 'Participo', icon: ICONS.ticket, show: (u) => !!u.user },
  { to: '/panel', label: 'Panel', icon: ICONS.store, show: (u) => u.isStaff || u.isOwner },
  { to: '/admin', label: 'Admin', icon: ICONS.shield, show: (u) => u.isOwner },
]

function Logo() {
  return (
    <Link to="/" className="flex items-center gap-2.5 font-semibold text-ink-900">
      <span className="grid h-8 w-8 place-items-center rounded-lg bg-accent-600 text-base font-bold text-white shadow-card">
        #
      </span>
      <span className="hidden tracking-tight sm:inline">{env.appName}</span>
    </Link>
  )
}

function DesktopNav() {
  const u = useAuth()
  return (
    <nav className="hidden items-center gap-1 md:flex" aria-label="Principal">
      {NAVS.filter((n) => n.show(u)).map((n) => (
        <NavLink
          key={n.to}
          to={n.to}
          end={n.end}
          className={({ isActive }) =>
            `rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
              isActive
                ? 'bg-accent-50 text-accent-700'
                : 'text-ink-500 hover:bg-ink-50 hover:text-ink-900'
            }`
          }
        >
          {n.label}
        </NavLink>
      ))}
    </nav>
  )
}

function UserArea() {
  const { user, profile, isAnonymous, isOwner, roleLabel, signOut } = useAuth()
  return (
    <div className="flex items-center gap-2">
      {user ? (
        <>
          {isAnonymous && (
            <Link to="/crear-cuenta">
              <Badge tone="accent">Crear cuenta</Badge>
            </Link>
          )}
          <Badge tone={isOwner ? 'accent' : 'neutral'} className="hidden sm:inline-flex">
            {roleLabel}
          </Badge>
          <span className="hidden max-w-36 truncate text-sm text-ink-600 lg:inline">
            {profile?.display_name || profile?.email || 'Invitado'}
          </span>
          <Button variant="ghost" size="sm" onClick={() => signOut().catch(() => {})}>
            Salir
          </Button>
        </>
      ) : (
        <Link to="/ingresar">
          <Button variant="secondary" size="sm">Ingresar</Button>
        </Link>
      )}
    </div>
  )
}

function MobileNav() {
  const u = useAuth()
  const navs = NAVS.filter((n) => n.show(u))
  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-30 border-t border-ink-200 bg-paper-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden"
      aria-label="Navegación móvil"
    >
      <div className="mx-auto grid max-w-lg" style={{ gridTemplateColumns: `repeat(${navs.length}, minmax(0,1fr))` }}>
        {navs.map((n) => (
          <NavLink
            key={n.to}
            to={n.to}
            end={n.end}
            className={({ isActive }) =>
              `flex flex-col items-center gap-1 py-2.5 text-[11px] font-medium transition-colors ${
                isActive ? 'text-accent-600' : 'text-ink-400 hover:text-ink-700'
              }`
            }
          >
            <Icon d={n.icon} className="h-5 w-5" />
            {n.label}
          </NavLink>
        ))}
      </div>
    </nav>
  )
}

export function AppLayout() {
  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-20 border-b border-ink-200 bg-paper-100/90 backdrop-blur">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center justify-between gap-4 px-4">
          <Logo />
          <DesktopNav />
          <UserArea />
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6 pb-24 md:pb-6">
        <Outlet />
      </main>

      <footer className="hidden border-t border-ink-200 py-6 md:block">
        <div className="mx-auto flex w-full max-w-6xl flex-col items-center justify-between gap-2 px-4 text-xs text-ink-400 sm:flex-row">
          <span>{env.appName} — sorteos simples, claros y auditables</span>
          <span className="flex gap-4">
            <Link to="/terminos" className="hover:text-ink-600">Términos</Link>
            <Link to="/privacidad" className="hover:text-ink-600">Privacidad</Link>
            <Link to="/reglas" className="hover:text-ink-600">Reglas</Link>
          </span>
        </div>
      </footer>

      <MobileNav />
    </div>
  )
}
