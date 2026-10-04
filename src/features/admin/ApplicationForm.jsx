import { useState } from 'react'
import { Link } from 'react-router-dom'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError } from '../../lib/sweetalert.js'
import { Card } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { Icon } from '../../components/ui/Icon.jsx'

/*
 * Formulario de contacto rápido: nombre, apellido y un contacto (email o
 * teléfono) + mensaje. Los datos completos del negocio se piden recién en el
 * onboarding, después de que el OWNER aprueba la solicitud.
 */
export function ApplicationForm() {
  const [form, setForm] = useState({ nombre: '', apellido: '', email: '', telefono: '', message: '' })
  const [error, setError] = useState(null)
  const [done, setDone] = useState(false)
  const [busy, setBusy] = useState(false)

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (form.nombre.trim().length < 2) return setError('Poné tu nombre.')
    if (form.apellido.trim().length < 2) return setError('Poné tu apellido.')
    if (!form.email.trim() && form.telefono.trim().length < 6) {
      return setError('Dejanos al menos un email o un teléfono.')
    }

    setBusy(true)
    try {
      await callRpc('application_submit', {
        p_nombre: form.nombre.trim(),
        p_apellido: form.apellido.trim(),
        p_email: form.email.trim() || null,
        p_negocio: null,
        p_dni: null,
        p_tax_type: null,
        p_tax_id: null,
        p_telefono: form.telefono.trim() || null,
        p_message: form.message.trim() || null,
      })
      setDone(true)
    } catch (err) {
      showRpcError(err, 'No se pudo enviar el mensaje')
    } finally {
      setBusy(false)
    }
  }

  if (done) {
    return (
      <Card>
        <div className="py-10 text-center">
          <div className="mx-auto mb-4 grid h-16 w-16 place-items-center rounded-full bg-available-50 text-available-600">
            <Icon name="check" size={30} />
          </div>
          <h2 className="text-xl font-bold text-ink-900">¡Mensaje enviado!</h2>
          <p className="mx-auto mt-2 max-w-sm text-sm text-ink-500">
            Te vamos a contactar por tu email o teléfono. Cuando esté todo listo,
            te registrás y publicás tu primer sorteo.
          </p>
          <Link to="/" className="mt-6 inline-block">
            <Button variant="secondary">Volver al inicio</Button>
          </Link>
        </div>
      </Card>
    )
  }

  return (
    <div className="mx-auto max-w-lg">
      <div className="mb-6 text-center">
        <Badge tone="accent">Quiero publicar sorteos</Badge>
        <h1 className="mt-3 text-2xl font-bold text-ink-900">Escribinos</h1>
        <p className="mt-1 text-sm text-ink-500">
          Dejanos tu nombre y un contacto. Te llamamos y te habilitamos la cuenta.
        </p>
      </div>

      <Card>
        <form onSubmit={onSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Input label="Nombre" value={form.nombre} onChange={set('nombre')} placeholder="Tu nombre" autoComplete="given-name" required />
          <Input label="Apellido" value={form.apellido} onChange={set('apellido')} placeholder="Tu apellido" autoComplete="family-name" required />
          <Input label="Email" type="email" value={form.email} onChange={set('email')} placeholder="vos@ejemplo.com" autoComplete="email" hint="O dejanos tu teléfono." />
          <Input label="Teléfono" value={form.telefono} onChange={set('telefono')} placeholder="+54 9 11 ..." autoComplete="tel" hint="O dejanos tu email." />
          <div className="flex flex-col gap-1.5 sm:col-span-2">
            <label htmlFor="msg" className="text-sm font-medium text-ink-700">
              Contanos qué querés sortear (opcional)
            </label>
            <textarea
              id="msg"
              value={form.message}
              onChange={set('message')}
              rows={3}
              className="rounded-md border border-ink-300 bg-paper-100 px-3 py-2 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
              placeholder="Ej: Rifas mensuales para mi local..."
            />
          </div>
          {error && <p className="text-sm text-error-500 sm:col-span-2" role="alert">{error}</p>}
          <div className="sm:col-span-2">
            <Button type="submit" size="lg" loading={busy} className="w-full sm:w-auto">
              Enviar mensaje <Icon name="arrowRight" size={18} />
            </Button>
          </div>
        </form>
      </Card>

      <p className="mt-4 text-center text-xs text-ink-400">
        Ya tenés cuenta? <Link to="/ingresar" className="font-medium text-accent-600 hover:underline">Ingresá</Link>
      </p>
    </div>
  )
}
