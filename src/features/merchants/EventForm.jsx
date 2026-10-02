import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { listDrawSources } from '../../services/supabase/queries/admin.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { slugify } from '../admin/CreateMerchantCard.jsx'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'

const WINNER_METHODS = [
  { value: 'RANDOM_SEEDED', label: 'Sorteo aleatorio del sistema (seed verificable)' },
  { value: 'MANUAL', label: 'Lo defino yo (a mano, con justificación y evidencia)' },
  { value: 'EXTERNAL_LOTTERY', label: 'Por una lotería de referencia' },
]

const WINNER_RULES = [
  { value: 'MODULO_RESTO', label: 'Por resto (módulo) — el clásico' },
  { value: 'EXTRACTO_EXACTO', label: 'El extracto exacto' },
{ value: 'ULTIMOS_DIGITOS', label: 'Últimos dígitos del extracto' },
]

export function EventForm({ merchantId, onCreated }) {
  const qc = useQueryClient()
  const [form, setForm] = useState({
    title: '', slug: '', numbers_from: 1, numbers_to: 100,
    price_per_number: 0, participation_ends_at: '', winner_method: 'RANDOM_SEEDED',
    winner_rule: 'MODULO_RESTO', draw_source_id: '',
  })
  const [error, setError] = useState(null)

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  // Loterías de referencia: la RLS muestra sólo las activas al comercio.
  const { data: drawSources } = useQuery({
    queryKey: ['draw-sources'],
    queryFn: listDrawSources,
  })

  const isExternal = form.winner_method === 'EXTERNAL_LOTTERY'

  const mutation = useMutation({
    mutationFn: (payload) => callRpc('event_create', { p_merchant_id: merchantId, p_payload: payload }),
    onSuccess: (data) => {
      showSuccess('Evento creado en borrador', 'Ahora agregale premios y publicalo.')
      qc.invalidateQueries({ queryKey: ['merchant-events', merchantId] })
      onCreated?.(data?.event_id)
    },
    onError: (e) => showRpcError(e, 'No se pudo crear el evento'),
  })

  function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (form.title.trim().length < 3) return setError('El título es muy corto.')
    const from = Number(form.numbers_from)
    const to = Number(form.numbers_to)
    if (!from || !to || from < 1 || to < from) return setError('El rango de números no es válido.')
    if (to - from + 1 > 5000) return setError('El máximo es 5000 números por evento.')
    if (!form.participation_ends_at) return setError('Falta la fecha de cierre.')
    if (new Date(form.participation_ends_at) <= new Date()) return setError('El cierre tiene que ser en el futuro.')
    if (isExternal && !form.draw_source_id) return setError('Elegí la lotería de referencia.')

    const slug = form.slug || slugify(form.title)
    const payload = {
      title: form.title.trim(),
      slug,
      numbers_from: from,
      numbers_to: to,
      price_per_number: Number(form.price_per_number) || 0,
      participation_ends_at: new Date(form.participation_ends_at).toISOString(),
      winner_method: form.winner_method,
    }
    if (isExternal) {
      payload.winner_rule = form.winner_rule
      payload.draw_source_id = form.draw_source_id
    }
    mutation.mutate(payload)
  }

  const selectCls =
    'h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20'

  return (
    <Card>
      <CardHeader title="Crear evento" subtitle="Un sorteo o rifa con números limitados." />
      <form onSubmit={onSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          label="Título"
          value={form.title}
          onChange={(e) => { set('title')(e); setForm((f) => ({ ...f, slug: slugify(e.target.value) })) }}
          placeholder="Sorteo de fin de mes"
          required
        />
        <Input
          label="Identificador (URL)"
          value={form.slug}
          onChange={set('slug')}
          placeholder="sorteo-fin-de-mes"
          hint="Minúsculas, números y guiones."
        />
        <Input label="Números desde" type="number" min="1" value={form.numbers_from} onChange={set('numbers_from')} required />
        <Input label="Números hasta" type="number" min="1" value={form.numbers_to} onChange={set('numbers_to')} required />
        <Input
          label="Precio por número"
          type="number" min="0" step="0.01"
          value={form.price_per_number}
          onChange={set('price_per_number')}
          hint="0 si es gratis."
        />
        <Input
          label="Cierre de participación"
          type="datetime-local"
          value={form.participation_ends_at}
          onChange={set('participation_ends_at')}
          required
        />

        <div className="flex flex-col gap-1.5 sm:col-span-2">
          <label htmlFor="wm" className="text-sm font-medium text-ink-700">Cómo se determina el ganador</label>
          <select id="wm" value={form.winner_method} onChange={set('winner_method')} className={selectCls}>
            {WINNER_METHODS.map((m) => (
              <option key={m.value} value={m.value}>{m.label}</option>
            ))}
          </select>
        </div>

        {isExternal && (
          <div className="flex flex-col gap-1.5">
            <label htmlFor="ds" className="text-sm font-medium text-ink-700">Lotería de referencia</label>
            <select id="ds" value={form.draw_source_id} onChange={set('draw_source_id')} className={selectCls} required>
              <option value="">Elegí una lotería…</option>
              {(drawSources || []).map((ds) => (
                <option key={ds.id} value={ds.id}>{ds.name}</option>
              ))}
            </select>
            {!(drawSources || []).length && (
              <p className="text-xs text-warn-700">
                No hay loterías activas. Usá el sorteo aleatorio o a mano, o pedile al propietario
                que active una lotería en la configuración.
              </p>
            )}
          </div>
        )}

        {isExternal && (
          <div className="flex flex-col gap-1.5">
            <label htmlFor="wr" className="text-sm font-medium text-ink-700">Cómo se calcula el número</label>
            <select id="wr" value={form.winner_rule} onChange={set('winner_rule')} className={selectCls}>
              {WINNER_RULES.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>
        )}

        {error && <p className="text-sm text-error-500 sm:col-span-2" role="alert">{error}</p>}
        <div className="sm:col-span-2">
          <Button type="submit" loading={mutation.isPending}>
            Crear evento
          </Button>
        </div>
      </form>
    </Card>
  )
}
