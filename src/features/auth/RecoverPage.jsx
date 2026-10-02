import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { AuthCard, authErrorMessage } from './AuthCard.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { Button } from '../../components/ui/Button.jsx'

export function RecoverPage() {
  const { resetPassword } = useAuth()
  const [email, setEmail] = useState('')
  const [error, setError] = useState(null)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      await resetPassword(email)
      setDone(true)
    } catch (err) {
      setError(authErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  if (done) {
    return (
      <AuthCard title="Revisá tu correo" subtitle="Te enviamos un enlace para restablecer tu contraseña.">
        <p className="text-sm text-ink-600">Si el email existe en la plataforma, el enlace llega en unos minutos.</p>
        <div className="mt-5">
          <Link to="/ingresar">
            <Button variant="secondary" className="w-full">Volver a ingresar</Button>
          </Link>
        </div>
      </AuthCard>
    )
  }

  return (
    <AuthCard title="Recuperar contraseña" subtitle="Te enviamos un enlace para elegir una nueva.">
      <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
        <Input
          label="Email"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="vos@ejemplo.com"
          required
        />
        {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
        <Button type="submit" size="lg" loading={loading} className="w-full">
          Enviar enlace
        </Button>
        <div className="text-center">
          <Link to="/ingresar" className="text-sm text-ink-500 hover:text-accent-600">Volver a ingresar</Link>
        </div>
      </form>
    </AuthCard>
  )
}
