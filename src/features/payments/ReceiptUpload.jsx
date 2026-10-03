import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../services/supabase/client.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { FileUploader } from '../../components/ui/FileUploader.jsx'
import { useAuth } from '../../app/providers/AuthProvider.jsx'

const BUCKET = 'receipts'

/*
 * Subir comprobante: va al bucket PRIVADO en la carpeta de la reserva
 * ({merchant_id}/{event_id}/{reservation_id}/{uuid}.{ext}) y después se
 * registra la metadata con receipt_attach, que valida que el path sea el
 * correcto y pasa la reserva a PAYMENT_SUBMITTED.
 */
export function ReceiptUpload({ reservation, onDone }) {
  const qc = useQueryClient()
  const { user } = useAuth()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  async function upload(file) {
    setError(null)
    if (!file) return
    if (!user) {
      setError('Necesitás una sesión para subir el comprobante.')
      return
    }

    setBusy(true)
    try {
      const ext = file.name.split('.').pop().toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg'
      const path = `${reservation.merchant_id}/${reservation.event_id}/${reservation.id}/${crypto.randomUUID()}.${ext}`

      const { error: upError } = await supabase.storage
        .from(BUCKET)
        .upload(path, file, { cacheControl: '3600', upsert: false })

      if (upError) {
        throw new Error(upError.message || 'No se pudo subir el archivo.')
      }

      await callRpc('receipt_attach', {
        p_reservation_id: reservation.id,
        p_storage_path: path,
        p_original_name: file.name,
        p_mime_type: file.type,
        p_size_bytes: file.size,
      })

      showSuccess('Comprobante enviado', 'Lo estamos revisando. Te avisamos cuando esté validado.')
      qc.invalidateQueries({ queryKey: ['my-reservations'] })
      onDone?.()
    } catch (e) {
      showRpcError(e, 'No se pudo enviar el comprobante')
      setError(e?.message || 'No se pudo enviar el comprobante.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-2">
      <FileUploader onSelect={upload} loading={busy} label="Subir comprobante" />
      {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
    </div>
  )
}
