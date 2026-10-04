import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { supabase } from '../../services/supabase/client.js'
import { getCurrentTerms } from '../../services/supabase/queries/terms.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'

/*
 * Onboarding: el solicitante cuya aplicacion fue APROBADA completa los datos
 * del negocio, ve su plan, acepta los ToS y queda como comerciante.
 */
export function OnboardingPage() {
  const navigate = useNavigate()
  const { profile } = useAuth()

  const { data: app, isLoading: loadingApp } = useQuery({
    queryKey: ['my-application', profile?.email],
    enabled: !!profile?.email,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('merchant_applications')
        .select('*')
        .ilike('email', profile.email)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })

  const { data: terms } = useQuery({
    queryKey: ['terms', 'TERMS'],
    queryFn: () => getCurrentTerms('TERMS'),
  })

  const [form, setForm] = useState({
    name: '', slug: '', taxType: 'CUIT', taxId: '',
    phone: '', whatsapp: '', instagram: '', payment: '',
  })
  const [accepted, setAccepted] = useState(false)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  if (loadingApp) return <LoadingState label="Cargando tu solicitud..." />

  if (!app) {
    return (
      <Card>
        <CardHeader title="No hay solicitud" subtitle="No encontramos una solicitud para tu email." />
      </Card>
    )
  }

  if (app.status === 'PENDING') {
    return (
      <Card>
        <CardHeader title="Tu solicitud esta en revision" subtitle="Te avisamos por email cuando la revisemos." />
      </Card>
    )
  }

  if (app.status === 'REJECTED') {
    return (
      <Card>
        <CardHeader title="Tu solicitud fue rechazada" subtitle={app.review_note || 'Sin motivo especificado.'} />
      </Card>
    )
  }

  if (app.status === 'COMPLETED') {
    return (
      <Card>
        <CardHeader title="Ya completaste tu alta" subtitle="Tu comercio ya esta activo." />
        <Button onClick={() => navigate('/panel')}>Ir al panel</Button>
      </Card>
    )
  }

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (form.name.trim().length < 2) return setError('Pone el nombre de tu comercio.')
    if (form.taxId.trim().length < 6) return setError('Falta el CUIT/CUIL.')
    if (form.phone.trim().length < 6) return setError('Falta el telefono.')
    if (!accepted) return setError('Tenes que aceptar los terminos y condiciones.')
    if (!terms) return setError('Los terminos no estan disponibles.')

    setBusy(true)
    try {
      await callRpc('terms_accept', {
        p_terms_version_id: terms.id,
      })

      await callRpc('application_complete', {
        p_application_id: app.id,
        p_merchant_name: form.name.trim(),
        p_merchant_slug: form.slug.trim() || undefined,
        p_tax_type: form.taxType,
        p_tax_id: form.taxId.trim(),
        p_contact_phone: form.phone.trim(),
        p_terms_version_id: terms.id,
        p_contact_whatsapp: form.whatsapp.trim() || undefined,
        p_contact_instagram: form.instagram.trim() || undefined,
        p_payment_instructions: form.payment.trim() || undefined,
      })

      showSuccess('Comercio creado', 'Ya podes crear tu primer sorteo.')
      navigate('/panel')
    } catch (err) {
      showRpcError(err, 'No se pudo completar el alta')
    } finally {
      setBusy(false)
    }
  }

  const selectCls =
    'h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20'

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div className="text-center">
        <h1 className="text-2xl font-bold text-ink-900">Completá el alta de tu comercio</h1>
        <p className="mt-1 text-sm text-ink-500">
          Tu solicitud fue aprobada. Configura tu comercio para empezar.
        </p>
        <div className="mt-3 flex items-center justify-center gap-2">
          <Badge tone="accent">Plan: {app.plan_code}</Badge>
          {app.plan_code === 'FREE' && (
            <Badge tone="warn">Los eventos se borran 30 dias despues del cierre</Badge>
          )}
        </div>
      </div>

      <Card>
        <CardHeader title="Datos del comercio" subtitle="Todo lo que vean tus participantes." />
        <form onSubmit={onSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Input
            label="Nombre del comercio"
            value={form.name}
            onChange={set('name')}
            placeholder={app.negocio}
            required
          />
          <Input
            label="Identificador (URL)"
            value={form.slug}
            onChange={set('slug')}
            placeholder="mi-negocio"
            hint="Minusculas, numeros y guiones. Dejar vacio = automatico."
          />
          <div className="flex flex-col gap-1.5">
            <label htmlFor="tt" className="text-sm font-medium text-ink-700">Tipo fiscal</label>
            <select id="tt" value={form.taxType} onChange={set('taxType')} className={selectCls}>
              <option value="CUIT">CUIT (comercio registrado)</option>
              <option value="CUIL">CUIL (persona)</option>
            </select>
          </div>
          <Input
            label="CUIT / CUIL"
            value={form.taxId}
            onChange={set('taxId')}
            placeholder={app.tax_type === 'CUIT' ? '30-...' : '20-...'}
            defaultValue={app.tax_id || ''}
            required
          />
          <Input
            label="Telefono de contacto"
            value={form.phone}
            onChange={set('phone')}
            placeholder={app.telefono}
            required
          />
          <Input
            label="WhatsApp (opcional)"
            value={form.whatsapp}
            onChange={set('whatsapp')}
            placeholder="+54 9 11 ..."
          />
          <Input
            label="Instagram (opcional)"
            value={form.instagram}
            onChange={set('instagram')}
            placeholder="@minegocio"
          />
          <div className="flex flex-col gap-1.5 sm:col-span-2">
            <label htmlFor="pay" className="text-sm font-medium text-ink-700">
              Como pagan tus participantes (alias, CBU, transferencia, etc)
            </label>
            <textarea
              id="pay"
              value={form.payment}
              onChange={set('payment')}
              rows={3}
              className="rounded-md border border-ink-300 bg-paper-100 px-3 py-2 text-ink-900"
              placeholder="Ej: Alias: mi.negocio / Mercado Pago: ..."
            />
          </div>

          {terms && (
            <details className="sm:col-span-2">
              <summary className="cursor-pointer text-sm font-medium text-ink-700">
                Ver los terminos y condiciones
              </summary>
              <p className="mt-2 max-h-52 overflow-y-auto whitespace-pre-line rounded-md bg-ink-50 p-3 text-xs text-ink-600">
                {terms.content}
              </p>
            </details>
          )}

          <label className="flex cursor-pointer items-start gap-2 text-sm text-ink-700 sm:col-span-2">
            <input
              type="checkbox"
              checked={accepted}
              onChange={(e) => setAccepted(e.target.checked)}
              className="mt-0.5 h-4 w-4"
            />
            <span>Acepto los terminos y condiciones y asumo la responsabilidad fiscal correspondiente.</span>
          </label>

          {error && <p className="text-sm text-error-500 sm:col-span-2" role="alert">{error}</p>}
          <div className="sm:col-span-2">
            <Button type="submit" size="lg" loading={busy}>
              Crear mi comercio
            </Button>
          </div>
        </form>
      </Card>
    </div>
  )
}
