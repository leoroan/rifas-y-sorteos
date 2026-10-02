import { useQuery } from '@tanstack/react-query'
import { listMerchants } from '../../services/supabase/queries/admin.js'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'
import { EmptyState } from '../../components/ui/EmptyState.jsx'
import { CreateMerchantCard } from './CreateMerchantCard.jsx'
import { AssignMerchantCard } from './AssignMerchantCard.jsx'

export function OwnerPage() {
  const { isOwner } = useAuth()
  const { data: merchants, isLoading } = useQuery({
    queryKey: ['merchants'],
    queryFn: listMerchants,
    enabled: isOwner,
  })

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-ink-900">Administración</h1>
        <Badge tone="accent">OWNER</Badge>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <CreateMerchantCard />
        <AssignMerchantCard merchants={merchants || []} />
      </div>

      <Card>
        <CardHeader title="Comercios" subtitle={merchants ? `${merchants.length} en total` : ''} />
        {isLoading ? (
          <LoadingState />
        ) : !merchants?.length ? (
          <EmptyState title="Todavía no hay comercios" description="Creá el primero arriba." />
        ) : (
          <ul className="divide-y divide-ink-100">
            {merchants.map((m) => (
              <li key={m.id} className="flex items-center justify-between gap-3 py-3">
                <div>
                  <p className="font-medium text-ink-900">{m.name}</p>
                  <p className="text-sm text-ink-500">/{m.slug} · {m.currency}</p>
                </div>
                <Badge tone={m.status === 'ACTIVE' ? 'available' : m.status === 'SUSPENDED' ? 'warn' : 'neutral'}>
                  {m.status === 'ACTIVE' ? 'Activo' : m.status === 'SUSPENDED' ? 'Suspendido' : 'Cerrado'}
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  )
}
