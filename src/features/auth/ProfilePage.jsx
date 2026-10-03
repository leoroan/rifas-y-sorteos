import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { supabase } from '../../services/supabase/client.js'
import { listMyReservations } from '../../services/supabase/queries/reservations.js'
import { showSuccess, showRpcError } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { RESERVATION_STATUS } from '../../constants/statuses.js'

async function myWonPrizes(profileId) {
  const { data, error } = await supabase
    .from('event_winners')
    .select('id, number, position, claim_status, prize:prize_id(title), event:event_id(title)')
    .eq('profile_id', profileId)
  if (error) throw error
  return data
}

function EditName({ profile }) {
  const qc = useQueryClient()
  const [name, setName] = useState(profile?.display_name ?? '')
  const [busy, setBusy] = useState(false)
  const [saved, setSaved] = useState(false)

  async function save(e) {
    e.preventDefault()
    setBusy(true)
    setSaved(false)
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ display_name: name.trim() })
        .eq('id', profile.id)
      if (error) throw error
      showSuccess('Nombre actualizado')
      setSaved(true)
      qc.invalidateQueries({ queryKey: ['profile'] })
    } catch (err) {
      showRpcError(err, 'No se pudo guardar')
    } finally {
      setBusy(false)
    }
  }

  return (
    <form onSubmit={save} className="flex items-end gap-2">
      <Input
        label="Nombre para mostrar"
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Tu nombre"
      />
      <Button type="submit" size="md" loading={busy}>
        {saved ? 'Guardado ✓' : 'Guardar'}
      </Button>
    </form>
  )
}

export function ProfilePage() {
  const { profile, isAnonymous, roleLabel } = useAuth()

  const { data: reservations, isLoading: loadingRes } = useQuery({
    queryKey: ['my-reservations'],
    queryFn: listMyReservations,
  })

  const { data: prizes, isLoading: loadingPrizes } = useQuery({
    queryKey: ['my-prizes', profile?.id],
    queryFn: () => myWonPrizes(profile.id),
    enabled: !!profile?.id,
  })

  if (!profile) return <LoadingState />

  const counts = (reservations || []).reduce(
    (acc, r) => {
      acc.total += 1
      if (r.status === RESERVATION_STATUS.APPROVED) acc.approved += 1
      if ([RESERVATION_STATUS.PENDING, RESERVATION_STATUS.PAYMENT_SUBMITTED].includes(r.status)) acc.open += 1
      return acc
    },
    { total: 0, approved: 0, open: 0 },
  )

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-2xl font-bold text-ink-900">Mi cuenta</h1>
        <Badge tone="accent">{roleLabel}</Badge>
        {isAnonymous && <Badge tone="warn">Sin cuenta</Badge>}
      </div>

      {isAnonymous && (
        <Card className="border-accent-200 bg-accent-50">
          <p className="text-sm text-accent-900">
            Estás participando <strong>sin cuenta</strong>.{' '}
            <Link to="/crear-cuenta" className="font-semibold underline">Creá una</Link>{' '}
            para conservar tu historial en cualquier dispositivo.
          </p>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-1">
          <CardHeader title="Mis datos" subtitle="Así te ve el comercio cuando participás." />
          <EditName profile={profile} />
          <dl className="mt-4 space-y-2 border-t border-ink-100 pt-4 text-sm">
            <div className="flex justify-between gap-2">
              <dt className="text-ink-500">Email</dt>
              <dd className="font-medium text-ink-800">{profile.email || '—'}</dd>
            </div>
            <div className="flex justify-between gap-2">
              <dt className="text-ink-500">Rol</dt>
              <dd className="font-medium text-ink-800">{roleLabel}</dd>
            </div>
            <div className="flex justify-between gap-2">
              <dt className="text-ink-500">Cuenta</dt>
              <dd className="font-medium text-ink-800">{isAnonymous ? 'Anónima' : 'Permanente'}</dd>
            </div>
          </dl>
        </Card>

        <div className="space-y-6 lg:col-span-2">
          <div className="grid grid-cols-3 gap-3">
            <Card padding="p-4">
              <div className="tnum text-2xl font-bold text-ink-900">{loadingRes ? '…' : counts.total}</div>
              <div className="text-xs text-ink-500">Participaciones</div>
            </Card>
            <Card padding="p-4">
              <div className="tnum text-2xl font-bold text-paid-700">{loadingRes ? '…' : counts.approved}</div>
              <div className="text-xs text-ink-500">Confirmadas</div>
            </Card>
            <Card padding="p-4">
              <div className="tnum text-2xl font-bold text-winner-700">{loadingPrizes ? '…' : (prizes || []).length}</div>
              <div className="text-xs text-ink-500">Premios ganados</div>
            </Card>
          </div>

          <Card>
            <CardHeader title="Premios ganados" subtitle={prizes?.length ? undefined : 'Todavía no ganaste ningún premio.'} />
            {loadingPrizes ? (
              <LoadingState />
            ) : prizes?.length ? (
              <ul className="divide-y divide-ink-100">
                {prizes.map((w) => (
                  <li key={w.id} className="flex items-center justify-between gap-3 py-3">
                    <div>
                      <p className="font-medium text-ink-900">{w.prize?.title ?? 'Premio'}</p>
                      <p className="text-sm text-ink-500">{w.event?.title}</p>
                    </div>
                    <span className="tnum rounded-md border border-winner-300 bg-winner-50 px-3 py-1 font-bold text-winner-700">
                      {w.number}
                    </span>
                  </li>
                ))}
              </ul>
            ) : null}
          </Card>

          <Card>
            <CardHeader title="Tus datos y tu privacidad" />
            <p className="text-sm leading-relaxed text-ink-500">
              Guardamos lo mínimo: tu email (si te registraste), un nombre para mostrar, tus reservas y los
              comprobantes que subís (en un espacio privado). Nunca tu IP en claro ni tus documentos.
              Podés leer más en la{' '}
              <Link to="/privacidad" className="font-medium text-accent-600">política de privacidad</Link>.
            </p>
          </Card>
        </div>
      </div>
    </div>
  )
}
