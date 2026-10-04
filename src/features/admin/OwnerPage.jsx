import { useState } from 'react'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { ComerciosSection } from './ComerciosSection.jsx'
import { ApplicationsCard } from './ApplicationsCard.jsx'
import { DrawSourcesCard } from './DrawSourcesCard.jsx'
import { CreateMerchantCard } from './CreateMerchantCard.jsx'
import { AssignMerchantCard } from './AssignMerchantCard.jsx'
import { listMerchants } from '../../services/supabase/queries/admin.js'
import { useQuery } from '@tanstack/react-query'

const TABS = [
  { id: 'comercios', label: 'Comercios' },
  { id: 'solicitudes', label: 'Solicitudes' },
  { id: 'equipo', label: 'Alta manual' },
  { id: 'loterias', label: 'Loterias' },
]

/*
 * Panel del OWNER, separado en secciones para no amontonar todo en una vista.
 * Cada tab es un dominio de administracion distinto.
 */
export function OwnerPage() {
  const { isOwner } = useAuth()
  const [tab, setTab] = useState('comercios')

  const { data: merchants } = useQuery({
    queryKey: ['merchants'],
    queryFn: listMerchants,
    enabled: isOwner,
  })

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-2xl font-bold text-ink-900">Administracion</h1>
        <Badge tone="accent">OWNER</Badge>
      </div>

      <nav className="flex flex-wrap gap-1 border-b border-ink-200 pb-2" aria-label="Secciones">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
              tab === t.id
                ? 'bg-accent-50 text-accent-700'
                : 'text-ink-500 hover:bg-ink-50 hover:text-ink-900'
            }`}
          >
            {t.label}
          </button>
        ))}
      </nav>

      {tab === 'comercios' && <ComerciosSection />}

      {tab === 'solicitudes' && <ApplicationsCard />}

      {tab === 'equipo' && (
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <CreateMerchantCard />
          <AssignMerchantCard merchants={merchants || []} />
        </div>
      )}

      {tab === 'loterias' && <DrawSourcesCard />}
    </div>
  )
}
