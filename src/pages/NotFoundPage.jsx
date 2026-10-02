import { Link } from 'react-router-dom'
import { Button } from '../components/ui/Button.jsx'

export function NotFoundPage() {
  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center text-center">
      <p className="tnum text-6xl font-bold text-ink-200">404</p>
      <h1 className="mt-2 text-xl font-semibold text-ink-900">No encontramos esa página</h1>
      <p className="mt-1 text-ink-500">Puede que el enlace esté mal o que el contenido ya no exista.</p>
      <Link to="/" className="mt-6">
        <Button>Volver al inicio</Button>
      </Link>
    </div>
  )
}
