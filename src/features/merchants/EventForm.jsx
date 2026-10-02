import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { slugify } from '../admin/CreateMerchantCard.jsx'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'

const WINNER_METHODS = [
  { value: 'RANDOM_SEEDED', label: 'Sorteo aleatorio del sistema (seed verificable)' },
  { value: 'MANUAL', label: 'Lo defino yo (a mano, con justificación)' },
  { value: 'EXTERNAL_LOTTERY', label: 'Por una lotería de referencia' },
]

export function EventForm({ merchantId, onCreated }) {
  const qc = useQueryClient()
  const [form, setForm] = useState({
    title: '', slug: '', numbers_from: 1, numbers_to: 100,
    price_per_number: 0, participation_ends_at: '', winner_method: 'RANDOM_SEEDED',
  })
  const [error, setError] = useState(null)

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

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

    const slug = form.slug || slugify(form.title)
    mutation.mutate({
      title: form.title.trim(),
      slug,
      numbers_from: from,
      numbers_to: to,
      price_per_number: Number(form.price_per_number) || 0,
      participation_ends_at: new Date(form.participation_ends_at).toISOString(),
      winner_method: form.winner_method,
    })
  }

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
          <select
            id="wm"
            value={form.winner_method}
            onChange={set('winner_method')}
            className="h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
          >
            {WINNER_METHODS.map((m) => (
              <option key={m.value} value={m.value}>{m.label}</option>
            ))}
          </select>
        </div>
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
