import { useQuery } from '@tanstack/react-query'
import { getCurrentTerms } from '../services/supabase/queries/terms.js'
import { LoadingState } from '../components/ui/LoadingState.jsx'
import { EmptyState } from '../components/ui/EmptyState.jsx'
import { Card, CardHeader } from '../components/ui/Card.jsx'
import { Badge } from '../components/ui/Badge.jsx'

const TITLES = {
  TERMS: 'Términos y condiciones',
  PRIVACY: 'Política de privacidad',
  PARTICIPATION_RULES: 'Reglas de participación',
}

export function LegalPage({ kind = 'TERMS' }) {
  const { data, isLoading } = useQuery({
    queryKey: ['terms', kind],
    queryFn: () => getCurrentTerms(kind),
  })

  if (isLoading) return <LoadingState />

  if (!data) {
    return <EmptyState title="No encontramos ese documento" description="Todavía no fue publicado." />
  }

  return (
    <div className="mx-auto max-w-3xl">
      <Card>
        <CardHeader
          title={TITLES[kind] || data.title}
          subtitle={`Versión ${data.version}`}
          action={<Badge tone="warn">Plantilla — requiere revisión legal</Badge>}
        />
        <article className="prose-sm max-w-none whitespace-pre-line text-ink-700">
          {data.content}
        </article>
        <p className="mt-6 border-t border-ink-100 pt-4 text-xs text-ink-400">
          Publicado: {new Date(data.published_at).toLocaleDateString('es-AR', { dateStyle: 'long' })}
        </p>
      </Card>
    </div>
  )
}
