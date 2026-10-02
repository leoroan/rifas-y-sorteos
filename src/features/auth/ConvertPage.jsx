import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { callRpc } from '../../lib/rpc.js'
import { AuthCard, authErrorMessage } from './AuthCard.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { Button } from '../../components/ui/Button.jsx'

/*
 * Conversión anónimo → registrado. El UUID NO cambia: el historial del
 * participante (reservas, comprobantes, premios) sobrevive entero.
 * Paso 1: vincular el email. Tras confirmarlo, paso 2: elegir contraseña.
 */
export function ConvertPage() {
  const { convertToRegistered, isAnonymous, user } = useAuth()
  const navigate = useNavigate()

  const [email, setEmail] = useState('')
  const [error, setError] = useState(null)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      await convertToRegistered({ email })
      // profile_mark_converted se ejecuta después de confirmar el email.
      try {
        await callRpc('profile_mark_converted')
      } catch {
        // Si el email aún no está confirmado, se marca al confirmar.
      }
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
          Cuando lo confirmes, tu cuenta queda permanente. <strong>Todo tu historial se conserva</strong>: reservas,
          comprobantes y premios.
        </p>
        <div className="mt-5">
          <Button className="w-full" onClick={() => navigate('/mis-participaciones')}>
            Ver mis participaciones
          </Button>
        </div>
      </AuthCard>
    )
  }

  if (!isAnonymous && user) {
    return (
      <AuthCard title="Ya tenés cuenta" subtitle="Tu cuenta ya es permanente.">
        <Button className="w-full" onClick={() => navigate('/mis-participaciones')}>
          Ver mis participaciones
        </Button>
      </AuthCard>
    )
  }

  return (
    <AuthCard
      title="Crear cuenta"
      subtitle="Convertí tu participación en una cuenta permanente. No perdés nada."
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-4" noValidate>
        <p className="text-sm text-ink-600">
          Tus reservas, comprobantes y premios <strong>siguen siendo tuyos</strong>. Sólo agregás un email y una
          contraseña para entrar desde cualquier dispositivo.
        </p>
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
          Crear cuenta
        </Button>
      </form>
    </AuthCard>
  )
}
