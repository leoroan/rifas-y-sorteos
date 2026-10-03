import { useState } from 'react'
import { Link } from 'react-router-dom'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'

/*
 * Formulario público para ser comerciante. No expone el email del OWNER:
 * el interesado completa, la solicitud queda PENDING y el OWNER la revisa
 * desde /admin/solicitudes.
 */
export function ApplicationForm() {
  const [form, setForm] = useState({
    nombre: '', apellido: '', email: '', negocio: '',
    dni: '', taxType: '', taxId: '', telefono: '', message: '',
  })
  const [error, setError] = useState(null)
  const [done, setDone] = useState(false)
  const [busy, setBusy] = useState(false)

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (form.nombre.trim().length < 2) return setError('Poné tu nombre.')
    if (form.apellido.trim().length < 2) return setError('Poné tu apellido.')
    if (!form.email.includes('@')) return setError('Poné un email válido.')
    if (form.negocio.trim().length < 2) return setError('Contanos el nombre de tu negocio.')
    if (form.telefono.trim().length < 6) return setError('Poné un teléfono de contacto.')
    if (form.taxType && form.taxId.trim().length < 6) return setError('Poné tu CUIT/CUIL.')

    setBusy(true)
    try {
      await callRpc('application_submit', {
        p_nombre: form.nombre.trim(),
        p_apellido: form.apellido.trim(),
        p_email: form.email.trim(),
        p_negocio: form.negocio.trim(),
        p_dni: form.dni.trim() || null,
        p_tax_type: form.taxType || null,
        p_tax_id: form.taxId.trim() || null,
        p_telefono: form.telefono.trim(),
        p_message: form.message.trim() || null,
      })
      setDone(true)
    } catch (err) {
      showRpcError(err, 'No se pudo enviar la solicitud')
    } finally {
      setBusy(false)
    }
  }

  if (done) {
    return (
      <Card>
        <div className="py-8 text-center">
          <div className="mx-auto mb-4 grid h-16 w-16 place-items-center rounded-full bg-available-50 text-3xl">✅</div>
          <h2 className="text-xl font-bold text-ink-900">¡Solicitud enviada!</h2>
          <p className="mx-auto mt-2 max-w-sm text-sm text-ink-500">
            Te vamos a contactar por email cuando la revisemos. Una vez aprobada,
            te registrás con ese email y completás los datos de tu comercio.
          </p>
          <Link to="/" className="mt-6 inline-block">
            <Button variant="secondary">Volver al inicio</Button>
          </Link>
        </div>
      </Card>
    )
  }

  const selectCls =
    'h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20'

  return (
    <Card>
      <CardHeader
        title="Quiero publicar sorteos"
        subtitle="Completá el formulario y te contactamos. Sin compromiso."
      />
      <form onSubmit={onSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input label="Nombre" value={form.nombre} onChange={set('nombre')} placeholder="Tu nombre" required />
        <Input label="Apellido" value={form.apellido} onChange={set('apellido')} placeholder="Tu apellido" required />
        <Input
          label="Email" type="email" value={form.email} onChange={set('email')}
          placeholder="vos@ejemplo.com" required
          hint="Te contactamos por este email."
        />
        <Input
          label="Nombre del negocio" value={form.negocio} onChange={set('negocio')}
          placeholder="Almacén Don Pedro" required
        />
        <Input label="Teléfono" value={form.telefono} onChange={set('telefono')} placeholder="+54 9 11 ..." required />
        <Input label="DNI (opcional)" value={form.dni} onChange={set('dni')} placeholder="Tu DNI" />
        <div className="flex flex-col gap-1.5">
          <label htmlFor="taxtype" className="text-sm font-medium text-ink-700">
            ¿Tenés CUIT o CUIL?
          </label>
          <select id="taxtype" value={form.taxType} onChange={set('taxType')} className={selectCls}>
            <option value="">Elegí una opción…</option>
            <option value="CUIT">CUIT (comercio registrado)</option>
            <option value="CUIL">CUIL (persona)</option>
          </select>
          {form.taxType && (
            <p className="text-xs text-ink-400">
              {form.taxType === 'CUIT'
                ? 'Como comercio registrado, sos responsable fiscal de las operaciones.'
                : 'Como persona, operás bajo tu CUIL con las responsabilidades correspondientes.'}
            </p>
          )}
        </div>
        <Input
          label="CUIT / CUIL"
          value={form.taxId} onChange={set('taxId')}
          placeholder={form.taxType === 'CUIT' ? '30-...' : form.taxType === 'CUIL' ? '20-...' : 'XX-XXXXXXXX-X'}
          required={!!form.taxType}
        />
        <div className="flex flex-col gap-1.5 sm:col-span-2">
          <label htmlFor="msg" className="text-sm font-medium text-ink-700">
            Contanos qué querés sortear (opcional)
          </label>
          <textarea
            id="msg" value={form.message} onChange={set('message')} rows={3}
            className="rounded-md border border-ink-300 bg-paper-100 px-3 py-2 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
            placeholder="Ej: Rifas mensuales para mi local..."
          />
        </div>
        {error && <p className="text-sm text-error-500 sm:col-span-2" role="alert">{error}</p>}
        <div className="sm:col-span-2">
          <Button type="submit" size="lg" loading={busy}>Enviar solicitud</Button>
        </div>
      </form>
    </Card>
  )
}
