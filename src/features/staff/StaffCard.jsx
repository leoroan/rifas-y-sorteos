import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../services/supabase/client.js'
import { callRpc } from '../../lib/rpc.js'
import { confirmDanger, showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'

const DELEGABLE = [
  { code: 'payment.receipt.review', label: 'Revisar comprobantes' },
  { code: 'reservation.confirm', label: 'Confirmar reservas' },
  { code: 'reservation.cancel', label: 'Cancelar reservas' },
  { code: 'prize.manage', label: 'Administrar premios' },
  { code: 'event.close', label: 'Cerrar eventos' },
  { code: 'stats.view', label: 'Ver estadísticas' },
]

async function listMembers(merchantId) {
  const { data, error } = await supabase
    .from('merchant_members')
    .select('id, profile_id, role, status, joined_at, profiles:profile_id(email, display_name)')
    .eq('merchant_id', merchantId)
    .order('joined_at', { ascending: true })
  if (error) throw error
  return data
}

async function listMemberPermissions(memberIds) {
  if (!memberIds.length) return []
  const { data, error } = await supabase
    .from('member_permissions')
    .select('merchant_member_id, permission_code, granted')
    .in('merchant_member_id', memberIds)
  if (error) throw error
  return data
}

function MemberRow({ member, perms, isMerchantOwner, onChanged }) {
  const qc = useQueryClient()
  const [busy, setBusy] = useState(false)
  const name = member.profiles?.display_name || member.profiles?.email || '—'
  const isMerchant = member.role === 'MERCHANT'
  const suspended = member.status === 'SUSPENDED'
  const removed = member.status === 'REMOVED'

  async function act(action, args = {}) {
    setBusy(true)
    try {
      if (action === 'status') {
        await callRpc('staff_set_status', {
          p_member_id: member.id,
          p_status: args.status,
          p_reason: args.reason || null,
        })
      } else if (action === 'perm') {
        await callRpc('staff_set_permission', {
          p_member_id: member.id,
          p_permission_code: args.code,
          p_granted: args.granted,
        })
      }
      qc.invalidateQueries({ queryKey: ['staff'] })
      onChanged?.()
    } catch (e) {
      showRpcError(e)
    } finally {
      setBusy(false)
    }
  }

  async function remove() {
    const ok = await confirmDanger({
      title: `¿Quitar a ${name}?`,
      text: 'Pierde el acceso al comercio. Su historial queda registrado.',
      confirmText: 'Quitar',
    })
    if (ok) act('status', { status: 'REMOVED', reason: 'Removido del equipo' })
  }

  function permGranted(code) {
    const p = perms.find((x) => x.merchant_member_id === member.id && x.permission_code === code)
    return p ? p.granted : true
  }

  if (removed) return null

  return (
    <li className="border-t border-ink-100 py-3 first:border-0">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Badge tone={isMerchant ? 'accent' : 'neutral'}>
            {isMerchant ? 'Organizador' : 'Colaborador'}
          </Badge>
          <span className="font-medium text-ink-900">{name}</span>
          {suspended && <Badge tone="warn">Suspendido</Badge>}
        </div>
        {!isMerchant && (
          <div className="flex items-center gap-1">
            <Button
              variant="ghost" size="sm" disabled={busy}
              onClick={() => act('status', { status: suspended ? 'ACTIVE' : 'SUSPENDED', reason: suspended ? null : 'Suspendido temporalmente' })}
            >
              {suspended ? 'Reactivar' : 'Suspender'}
            </Button>
            <Button variant="danger" size="sm" onClick={remove} disabled={busy}>
              Quitar
            </Button>
          </div>
        )}
      </div>

      {!isMerchant && isMerchantOwner && !suspended && (
        <div className="mt-2 flex flex-wrap gap-2">
          {DELEGABLE.map((d) => {
            const granted = permGranted(d.code)
            return (
              <button
                key={d.code}
                type="button"
                disabled={busy}
                onClick={() => act('perm', { code: d.code, granted: !granted })}
                className={`rounded-full border px-2.5 py-1 text-xs font-medium transition-colors ${
                  granted
                    ? 'border-accent-300 bg-accent-50 text-accent-700'
                    : 'border-ink-200 bg-paper-100 text-ink-400'
                }`}
                title={granted ? `Quitar: ${d.label}` : `Dar: ${d.label}`}
              >
                {d.label}
              </button>
            )
          })}
        </div>
      )}
    </li>
  )
}

/*
 * Equipo del comercio: organizadores y colaboradores. Un colaborador nunca
 * puede crear otro organizador (eso es sólo del OWNER), y sus permisos se
 * delegan dentro del techo del rol MERCHANT (la RPC lo hace cumplir).
 */
export function StaffCard({ merchantId }) {
  const qc = useQueryClient()
  const [email, setEmail] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  const { data: members, isLoading } = useQuery({
    queryKey: ['staff', merchantId],
    queryFn: () => listMembers(merchantId),
    enabled: !!merchantId,
  })

  const ids = (members || []).map((m) => m.id)
  const { data: perms } = useQuery({
    queryKey: ['staff-perms', ids.join(',')],
    queryFn: () => listMemberPermissions(ids),
    enabled: ids.length > 0,
  })

  const ownerMember = (members || []).find((m) => m.role === 'MERCHANT' && m.status === 'ACTIVE')
  const isOwnerView = !!ownerMember

  async function add(e) {
    e.preventDefault()
    setError(null)
    if (!email) return setError('Ingresá el email del colaborador.')
    setBusy(true)
    try {
      await callRpc('staff_add', {
        p_merchant_id: merchantId,
        p_email: email.trim(),
        p_role: 'COLLABORATOR',
      })
      showSuccess('Colaborador agregado', `${email.trim()} ya puede ayudar en el comercio.`)
      setEmail('')
      qc.invalidateQueries({ queryKey: ['staff'] })
    } catch (err) {
      showRpcError(err, 'No se pudo agregar')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card>
      <CardHeader
        title="Equipo"
        subtitle="Quién trabaja en tu comercio y qué puede hacer."
      />
      {isLoading ? (
        <LoadingState />
      ) : (
        <ul>
          {(members || []).map((m) => (
            <MemberRow key={m.id} member={m} perms={perms || []} isMerchantOwner={isOwnerView} />
          ))}
        </ul>
      )}

      {isOwnerView && (
        <form onSubmit={add} className="mt-4 border-t border-ink-100 pt-4">
          <div className="flex items-end gap-2">
            <Input
              label="Agregar colaborador (email)"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="colaborador@ejemplo.com"
              hint="Tiene que tener una cuenta registrada."
            />
            <Button type="submit" size="md" loading={busy}>
              Agregar
            </Button>
          </div>
          {error && <p className="mt-1 text-sm text-error-500" role="alert">{error}</p>}
          <p className="mt-2 text-xs text-ink-400">
            El colaborador no puede crear organizadores ni tocar la configuración global. Sus permisos se
            delegan con los botones de arriba, dentro del techo del organizador.
          </p>
        </form>
      )}
    </Card>
  )
}
