import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../services/supabase/client.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'

const PLANS = ['FREE', 'BASIC', 'INTERMEDIATE', 'PRO']
const STATUS_LABEL = { PENDING: 'Pendiente', APPROVED: 'Aprobada', REJECTED: 'Rechazada', COMPLETED: 'Completada' }
const STATUS_TONE = { PENDING: 'warn', APPROVED: 'accent', REJECTED: 'error', COMPLETED: 'paid' }

async function listApplications() {
  const { data, error } = await supabase
    .from('merchant_applications')
    .select('*')
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
}

function InfoLine({ app }) {
  const parts = [app.negocio, app.email, 'Tel: ' + app.telefono]
  if (app.tax_type) parts.push(app.tax_type + ': ' + app.tax_id)
  return <p className="text-sm text-ink-500">{parts.join(' | ')}</p>
}

function ReviewRow({ app, onReviewed }) {
  const [busy, setBusy] = useState(false)
  const [plan, setPlan] = useState(app.plan_code || 'FREE')
  const [note, setNote] = useState('')
  const [rejecting, setRejecting] = useState(false)

  async function review(decision, reviewNote) {
    setBusy(true)
    try {
      await callRpc('application_review', {
        p_application_id: app.id,
        p_decision: decision,
        p_plan_code: decision === 'APPROVE' ? plan : undefined,
        p_note: reviewNote || undefined,
      })
      showSuccess(decision === 'APPROVE' ? 'Solicitud aprobada' : 'Solicitud rechazada')
      onReviewed()
    } catch (e) {
      showRpcError(e)
    } finally {
      setBusy(false)
      setRejecting(false)
    }
  }

  if (app.status !== 'PENDING') {
    return (
      <div className="flex items-center justify-between gap-3 border-t border-ink-100 py-3 first:border-0">
        <div className="min-w-0">
          <p className="font-medium text-ink-900">{app.nombre} {app.apellido}</p>
          <InfoLine app={app} />
        </div>
        <Badge tone={STATUS_TONE[app.status] || 'neutral'}>{STATUS_LABEL[app.status] || app.status}</Badge>
      </div>
    )
  }

  return (
    <div className="border-t border-ink-100 py-4 first:border-0">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-semibold text-ink-900">{app.nombre} {app.apellido}</p>
          <InfoLine app={app} />
          {app.message ? <p className="mt-2 rounded-md bg-ink-50 p-2 text-sm text-ink-600">{app.message}</p> : null}
        </div>
        <Badge tone="warn">Pendiente</Badge>
      </div>
      {rejecting ? (
        <div className="mt-3 flex items-end gap-2">
          <input
            type="text"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Motivo (minimo 5 caracteres)"
            className="h-10 flex-1 rounded-md border border-ink-300 bg-paper-100 px-3 text-sm"
          />
          <Button variant="danger" size="sm" loading={busy} onClick={() => review('REJECT', note)}>
            Rechazar
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setRejecting(false)}>
            Cancelar
          </Button>
        </div>
      ) : (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <select
            value={plan}
            onChange={(e) => setPlan(e.target.value)}
            className="h-9 rounded-md border border-ink-300 bg-paper-100 px-2 text-sm"
          >
            {PLANS.map((p) => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
          <Button size="sm" loading={busy} onClick={() => review('APPROVE')}>
            Aprobar
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setRejecting(true)}>
            Rechazar
          </Button>
        </div>
      )}
    </div>
  )
}

export function ApplicationsCard() {
  const qc = useQueryClient()
  const { data: apps, isLoading } = useQuery({
    queryKey: ['applications'],
    queryFn: listApplications,
  })

  const pending = (apps || []).filter((a) => a.status === 'PENDING')
  const reviewed = (apps || []).filter((a) => a.status !== 'PENDING')

  return (
    <Card>
      <CardHeader
        title="Solicitudes de comerciantes"
        subtitle={pending.length ? pending.length + ' pendiente(s)' : 'Sin pendientes'}
      />
      {isLoading ? (
        <LoadingState />
      ) : !apps || apps.length === 0 ? (
        <p className="text-sm text-ink-400">Todavia no hay solicitudes.</p>
      ) : (
        <div>
          {pending.map((a) => (
            <ReviewRow key={a.id} app={a} onReviewed={() => qc.invalidateQueries({ queryKey: ['applications'] })} />
          ))}
          {reviewed.map((a) => (
            <ReviewRow key={a.id} app={a} />
          ))}
        </div>
      )}
    </Card>
  )
}
