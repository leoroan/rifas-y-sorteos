import { useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { AuthCard, authErrorMessage } from './AuthCard.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { Button } from '../../components/ui/Button.jsx'

export function LoginPage() {
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = location.state?.from?.pathname || '/mis-participaciones'

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (!email || !password) {
      setError('Completá tu email y tu contraseña.')
      return
    }
    setLoading(true)
    try {
      await signIn({ email, password })
      navigate(from, { replace: true })
    } catch (err) {
      setError(authErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthCard
      title="Ingresar"
      subtitle="Entrá con tu cuenta para ver tus participaciones."
      footer={
        <>
          ¿No tenés cuenta? <Link to="/registrarse" className="font-medium text-accent-600">Registrate</Link>
        </>
      }
    >
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
        <Input
          label="Contraseña"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="••••••••"
          required
        />
        {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
        <Button type="submit" size="lg" loading={loading} className="w-full">
          Ingresar
        </Button>
        <div className="text-center">
          <Link to="/recuperar" className="text-sm text-ink-500 hover:text-accent-600">
            Olvidé mi contraseña
          </Link>
        </div>
      </form>
    </AuthCard>
  )
}
