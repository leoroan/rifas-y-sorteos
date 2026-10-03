import { Link } from 'react-router-dom'
import { useNotifications } from './useNotifications.js'

function BellIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round" className="h-5 w-5" aria-hidden="true">
      <path d="M18 8a6 6 0 1 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" />
      <path d="M13.7 21a2 2 0 0 1-3.4 0" />
    </svg>
  )
}

/*
 * Campana con contador de no leídas. Lleva a la bandeja.
 */
export function NotificationBell() {
  const { data } = useNotifications()
  const unread = data?.unread ?? 0

  return (
    <Link
      to="/notificaciones"
      className="relative grid h-9 w-9 place-items-center rounded-lg text-ink-500 transition-colors hover:bg-ink-50 hover:text-ink-900"
      aria-label={unread > 0 ? `Notificaciones, ${unread} sin leer` : 'Notificaciones'}
    >
      <BellIcon />
      {unread > 0 && (
        <span className="absolute -right-0.5 -top-0.5 grid h-5 min-w-5 place-items-center rounded-full bg-error-500 px-1 text-[10px] font-bold text-white">
          {unread > 99 ? '99+' : unread}
        </span>
      )}
    </Link>
  )
}
