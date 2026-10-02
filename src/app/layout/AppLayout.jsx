import { Link, NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../providers/AuthProvider.jsx'
import { env } from '../config/env.js'
import { Button } from '../../components/ui/Button.jsx'
import { Badge } from '../../components/ui/Badge.jsx'

function NavItem({ to, children, end = false }) {
  return (
    <NavLink
      to={to}
      end={end}
      className={({ isActive }) =>
        `rounded-md px-3 py-2 text-sm font-medium transition-colors ${
          isActive ? 'bg-ink-100 text-ink-900' : 'text-ink-500 hover:bg-ink-50 hover:text-ink-800'
        }`
      }
    >
      {children}
    </NavLink>
  )
}

export function AppLayout() {
  const { user, profile, isAnonymous, isOwner, signOut } = useAuth()

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-20 border-b border-ink-200 bg-paper-100/90 backdrop-blur">
        <div className="mx-auto flex h-14 w-full max-w-6xl items-center justify-between gap-4 px-4">
          <Link to="/" className="flex items-center gap-2 font-semibold text-ink-900">
            <span className="grid h-7 w-7 place-items-center rounded-md bg-accent-600 text-sm font-bold text-white" aria-hidden="true">
              #
            </span>
            <span className="hidden sm:inline">{env.appName}</span>
          </Link>

          <nav className="flex items-center gap-1" aria-label="Principal">
            <NavItem to="/" end>
              Inicio
            </NavItem>
            {user && <NavItem to="/mis-participaciones">Mis participaciones</NavItem>}
            {isOwner && <NavItem to="/admin">Admin</NavItem>}
          </nav>

          <div className="flex items-center gap-2">
            {user ? (
              <>
                {isAnonymous && (
                  <Link to="/crear-cuenta">
                    <Badge tone="accent">Crear cuenta</Badge>
                  </Link>
                )}
                <span className="hidden max-w-40 truncate text-sm text-ink-600 sm:inline">
                  {profile?.display_name || profile?.email || 'Invitado'}
                </span>
                <Button variant="ghost" size="sm" onClick={() => signOut().catch(() => {})}>
                  Salir
                </Button>
              </>
            ) : (
              <Link to="/ingresar">
                <Button variant="secondary" size="sm">
                  Ingresar
                </Button>
              </Link>
            )}
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-6">
        <Outlet />
      </main>

      <footer className="border-t border-ink-200 py-6">
        <div className="mx-auto flex w-full max-w-6xl flex-col items-center justify-between gap-2 px-4 text-xs text-ink-400 sm:flex-row">
          <span>{env.appName} — sorteos simples, claros y auditables</span>
          <span className="flex gap-4">
            <Link to="/terminos" className="hover:text-ink-600">Términos</Link>
            <Link to="/privacidad" className="hover:text-ink-600">Privacidad</Link>
            <Link to="/reglas" className="hover:text-ink-600">Reglas</Link>
          </span>
        </div>
      </footer>
    </div>
  )
}
