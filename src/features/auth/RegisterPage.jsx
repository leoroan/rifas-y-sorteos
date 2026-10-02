import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { AuthCard, authErrorMessage } from './AuthCard.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { Button } from '../../components/ui/Button.jsx'

export function RegisterPage() {
  const { signUp } = useAuth()
  const navigate = useNavigate()

  const [displayName, setDisplayName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (password.length < 6) {
      setError('La contraseña tiene que tener al menos 6 caracteres.')
      return
    }
    setLoading(true)
    try {
      await signUp({ email, password, displayName })
      setDone(true)
    } catch (err) {
      setError(authErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  if (done) {
    return (
      <AuthCard title="Revisá tu correo" subtitle="Te enviamos un enlace para confirmar tu cuenta.">
        <p className="text-sm text-ink-600">
          Cuando lo confirmes, tu cuenta queda activa y podés participar en cualquier sorteo.
        </p>
        <div className="mt-5">
          <Button className="w-full" onClick={() => navigate('/ingresar')}>
            Ir a ingresar
          </Button>
        </div>
      </AuthCard>
    )
  }

  return (
    <AuthCard
      title="Crear cuenta"
      subtitle="Para seguir tus números y tus premios."
      footer={
        <>
          ¿Ya tenés cuenta? <Link to="/ingresar" className="font-medium text-accent-600">Ingresá</Link>
        </>
      }
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
        <Input
          label="Nombre"
          autoComplete="name"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          placeholder="Tu nombre"
        />
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
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Mínimo 6 caracteres"
          hint="Mínimo 6 caracteres."
          required
        />
        {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
        <Button type="submit" size="lg" loading={loading} className="w-full">
          Crear cuenta
        </Button>
        <p className="text-center text-xs text-ink-400">
          Al crear tu cuenta aceptás los <Link to="/terminos" className="underline">términos</Link> y la{' '}
          <Link to="/privacidad" className="underline">política de privacidad</Link>.
        </p>
      </form>
    </AuthCard>
  )
}
