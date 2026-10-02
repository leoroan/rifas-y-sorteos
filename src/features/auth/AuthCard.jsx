import { Link } from 'react-router-dom'

export function AuthCard({ title, subtitle, children, footer }) {
  return (
    <div className="mx-auto flex max-w-md flex-col">
      <div className="mb-6 text-center">
        <Link to="/" className="inline-grid h-10 w-10 place-items-center rounded-md bg-accent-600 text-lg font-bold text-white">
          #
        </Link>
        <h1 className="mt-4 text-2xl font-bold text-ink-900">{title}</h1>
        {subtitle ? <p className="mt-1 text-sm text-ink-500">{subtitle}</p> : null}
      </div>
      <div className="rounded-lg border border-ink-200 bg-paper-100 p-6 shadow-card">{children}</div>
      {footer ? <div className="mt-4 text-center text-sm text-ink-500">{footer}</div> : null}
    </div>
  )
}

export function authErrorMessage(error) {
  const msg = (error?.message || '').toLowerCase()
  if (msg.includes('invalid login credentials')) return 'Email o contraseña incorrectos.'
  if (msg.includes('email not confirmed')) return 'Tenés que confirmar tu email primero. Revisá tu correo.'
  if (msg.includes('user already registered')) return 'Ya existe una cuenta con ese email. ¿Querés ingresar?'
  if (msg.includes('password') && msg.includes('characters')) return 'La contraseña tiene que tener al menos 6 caracteres.'
  if (msg.includes('rate limit')) return 'Demasiados intentos. Esperá un momento y probá de nuevo.'
  return error?.message || 'Ocurrió un error. Probá de nuevo.'
}
