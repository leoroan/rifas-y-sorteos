import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { findProfileByEmail } from '../../services/supabase/queries/admin.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'

export function AssignMerchantCard({ merchants }) {
  const qc = useQueryClient()
  const { refreshProfile } = useAuth()
  const [merchantId, setMerchantId] = useState('')
  const [email, setEmail] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (!merchantId) return setError('Elegí un comercio.')
    if (!email) return setError('Ingresá el email del comerciante.')
    setBusy(true)
    try {
      const profile = await findProfileByEmail(email)
      if (profile) {
        await callRpc('admin_assign_merchant', { p_profile_id: profile.id, p_merchant_id: merchantId })
        showSuccess('Comerciante asignado', `${profile.email} ya puede administrar el comercio.`)
      } else {
        await callRpc('staff_invite', { p_merchant_id: merchantId, p_email: email.trim(), p_role: 'MERCHANT' })
        showSuccess(
          'Invitación enviada',
          `${email.trim()} va a poder administrar el comercio apenas se registre con ese email.`,
        )
      }
      setEmail('')
      qc.invalidateQueries({ queryKey: ['merchants'] })
      qc.invalidateQueries({ queryKey: ['merchant-invites'] })
      refreshProfile()
    } catch (err) {
      showRpcError(err, 'No se pudo asignar')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <CardHeader title="Asignar comerciante" subtitle="Sólo el OWNER puede otorgar el rol de comerciante." />
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="merchant" className="text-sm font-medium text-ink-700">Comercio</label>
          <select
            id="merchant"
            value={merchantId}
            onChange={(e) => setMerchantId(e.target.value)}
            className="h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
            required
          >
            <option value="">Elegí un comercio…</option>
            {merchants.map((m) => (
              <option key={m.id} value={m.id}>{m.name}</option>
            ))}
          </select>
        </div>
        <Input
          label="Email del comerciante"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="comerciante@ejemplo.com"
          hint="Si no está registrado, se le manda una invitación: entra apenas se registre."
          required
        />
        {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
        <Button type="submit" loading={busy} className="self-start">
          Asignar como comerciante
        </Button>
      </form>
    </Card>
  )
}
