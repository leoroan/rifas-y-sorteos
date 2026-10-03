import { useQuery } from '@tanstack/react-query'
import { supabase } from '../../services/supabase/client.js'
import { Card } from '../../components/ui/Card.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'

async function merchantStats(merchantId) {
  const [pendingReceipts, openReservations, events, approved] = await Promise.all([
    supabase.from('payment_receipts').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).eq('status', 'PENDING'),
    supabase.from('reservations').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).in('status', ['PENDING','PAYMENT_SUBMITTED']),
    supabase.from('events').select('id', { count: 'exact', head: true }).eq('merchant_id', merchantId).in('status', ['PUBLISHED','OPEN']),
    supabase.from('reservations').select('total_amount', { count: 'exact' }).eq('merchant_id', merchantId).eq('status', 'APPROVED'),
  ])
  const revenue = (approved.data || []).reduce((acc, r) => acc + Number(r.total_amount || 0), 0)
  return {
    pendingReceipts: pendingReceipts.count ?? 0,
    openReservations: openReservations.count ?? 0,
    activeEvents: events.count ?? 0,
    revenue,
  }
}

export function MerchantStats({ merchantId }) {
  const { data, isLoading } = useQuery({
    queryKey: ['merchant-stats', merchantId],
    queryFn: () => merchantStats(merchantId),
    enabled: !!merchantId,
    refetchInterval: 30_000,
  })

  if (isLoading) return <LoadingState />

  const items = [
    { label: 'Recaudación (aprobada)', value: data ? `$${data.revenue}` : '—', strong: true },
    { label: 'Comprobantes por revisar', value: data?.pendingReceipts ?? 0, strong: data?.pendingReceipts > 0 },
    { label: 'Reservas abiertas', value: data?.openReservations ?? 0 },
    { label: 'Eventos activos', value: data?.activeEvents ?? 0 },
  ]

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {items.map((it) => (
        <Card key={it.label} padding="p-4">
          <div className={`tnum text-xl font-bold ${it.strong ? 'text-accent-700' : 'text-ink-900'}`}>{it.value}</div>
          <div className="text-xs text-ink-500">{it.label}</div>
        </Card>
      ))}
    </div>
  )
}
