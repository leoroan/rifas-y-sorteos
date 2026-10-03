import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../services/supabase/client.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import Swal from 'sweetalert2'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'

async function listPendingReceipts(merchantId) {
  const { data, error } = await supabase
    .from('payment_receipts')
    .select('id, storage_path, original_name, mime_type, size_bytes, created_at, uploaded_by, reservation:reservation_id(id, number_count, total_amount, currency, expires_at)')
    .eq('merchant_id', merchantId)
    .eq('status', 'PENDING')
    .order('created_at', { ascending: true })
  if (error) throw error
  return data
}

async function signedUrl(path) {
  const { data, error } = await supabase.storage
    .from('receipts')
    .createSignedUrl(path, 60)
  if (error) throw error
  return data.signedUrl
}

function ReceiptRow({ r, onReviewed }) {
  const qc = useQueryClient()
  const [busy, setBusy] = useState(false)

  async function decide(decision, reason = null) {
    setBusy(true)
    try {
      await callRpc('review_receipt', {
        p_receipt_id: r.id,
        p_decision: decision,
        p_reason: reason,
      })
      showSuccess(
        decision === 'APPROVE' ? 'Pago aprobado' : decision === 'REJECT' ? 'Comprobante rechazado' : 'Corrección solicitada',
      )
      qc.invalidateQueries({ queryKey: ['pending-receipts'] })
      qc.invalidateQueries({ queryKey: ['merchant-events'] })
      onReviewed?.()
    } catch (e) {
      showRpcError(e)
    } finally {
      setBusy(false)
    }
  }

  async function view() {
    try {
      const url = await signedUrl(r.storage_path)
      window.open(url, '_blank', 'noopener')
    } catch (e) {
      showRpcError(e, 'No se pudo abrir el comprobante')
    }
  }

  async function reject() {
    const { value: reason, isConfirmed } = await Swal.fire({
      title: 'Rechazar comprobante',
      input: 'textarea',
      inputLabel: 'Motivo (se lo ve el participante)',
      inputPlaceholder: 'Ej: el importe no coincide con el total',
      inputValidator: (v) => (!v || v.trim().length < 5 ? 'Indicá un motivo de al menos 5 caracteres' : undefined),
      showCancelButton: true,
      confirmButtonText: 'Rechazar',
      confirmButtonColor: '#dd3a3a',
    })
    if (isConfirmed) decide('REJECT', reason)
  }

  async function askCorrection() {
    const { value: reason, isConfirmed } = await Swal.fire({
      title: 'Pedir corrección',
      input: 'textarea',
      inputLabel: 'Qué tiene que corregir el participante',
      inputPlaceholder: 'Ej: la imagen se ve borrosa, volvé a subirla',
      inputValidator: (v) => (!v || v.trim().length < 5 ? 'Indicá un motivo de al menos 5 caracteres' : undefined),
      showCancelButton: true,
      confirmButtonText: 'Pedir corrección',
    })
    if (isConfirmed) decide('REQUEST_CORRECTION', reason)
  }

  return (
    <li className="flex flex-col gap-3 py-3 sm:flex-row sm:items-center sm:justify-between">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <Badge tone="submitted">En revisión</Badge>
          <span className="tnum text-sm font-semibold text-ink-800">
            ${r.reservation?.total_amount} {r.reservation?.currency}
          </span>
          <span className="text-sm text-ink-500">· {r.reservation?.number_count} número(s)</span>
        </div>
        <p className="mt-1 truncate text-sm text-ink-500">
          {r.original_name || 'comprobante'} ·{' '}
          {new Date(r.created_at).toLocaleString('es-AR', { dateStyle: 'short', timeStyle: 'short' })}
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Button variant="ghost" size="sm" onClick={view}>
          Ver archivo
        </Button>
        <Button variant="ghost" size="sm" onClick={askCorrection} disabled={busy}>
          Corrección
        </Button>
        <Button variant="danger" size="sm" onClick={reject} disabled={busy}>
          Rechazar
        </Button>
        <Button size="sm" onClick={() => decide('APPROVE')} loading={busy}>
          Aprobar
        </Button>
      </div>
    </li>
  )
}

/*
 * Comprobantes pendientes de revisión para el comercio. El archivo se abre
 * con URL firmada (60 s) de la sesión del staff: la RLS de Storage decide si
 * podés verlo. La aprobación/rechazo/corrección pasa por review_receipt, que
 * también mueve la reserva y los números.
 */
export function ReceiptsCard({ merchantId }) {
  const { data: receipts, isLoading } = useQuery({
    queryKey: ['pending-receipts', merchantId],
    queryFn: () => listPendingReceipts(merchantId),
    enabled: !!merchantId,
    refetchInterval: 30_000,
  })

  return (
    <Card>
      <CardHeader
        title="Comprobantes por revisar"
        subtitle={receipts?.length ? `${receipts.length} en espera` : 'Al día'}
      />
      {isLoading ? (
        <LoadingState />
      ) : !receipts?.length ? (
        <EmptyState title="No hay comprobantes pendientes" description="Cuando un participante suba uno, aparece acá." />
      ) : (
        <ul className="divide-y divide-ink-100">
          {receipts.map((r) => (
            <ReceiptRow key={r.id} r={r} />
          ))}
        </ul>
      )}
    </Card>
  )
}
