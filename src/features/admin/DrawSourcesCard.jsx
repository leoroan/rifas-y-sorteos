import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { listDrawSources } from '../../services/supabase/queries/admin.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'
import { LoadingState } from '../../components/ui/LoadingState.jsx'

const KINDS = [
  { value: 'NATIONAL', label: 'Nacional' },
  { value: 'PROVINCIAL', label: 'Provincial' },
  { value: 'MUNICIPAL', label: 'Municipal' },
  { value: 'PRIVATE', label: 'Privada / propia' },
  { value: 'OTHER', label: 'Otra' },
]

const KIND_LABEL = Object.fromEntries(KINDS.map((k) => [k.value, k.label]))

/*
 * Loterías de referencia disponibles para los comercios al armar un evento.
 * Sólo las ACTIVAS se ofrecen en el formulario de eventos (eso lo decide la
 * RLS, no la UI). El catálogo vive en la base; acá el OWNER lo administra.
 */
export function DrawSourcesCard() {
  const qc = useQueryClient()
  const [adding, setAdding] = useState(false)
  const [form, setForm] = useState({
    code: '', name: '', kind: 'PROVINCIAL', jurisdiction: '',
    shifts: 'MATUTINA,VESPERTINA,NOCTURNA',
  })
  const [error, setError] = useState(null)

  const { data: sources, isLoading } = useQuery({
    queryKey: ['draw-sources-admin'],
    queryFn: listDrawSources,
  })

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['draw-sources-admin'] })
    qc.invalidateQueries({ queryKey: ['draw-sources'] })
  }

  const save = useMutation({
    mutationFn: (payload) => callRpc('admin_draw_source_upsert', { p_payload: payload }),
    onSuccess: () => {
      showSuccess('Lotería guardada')
      invalidate()
      setAdding(false)
      setForm({ code: '', name: '', kind: 'PROVINCIAL', jurisdiction: '', shifts: 'MATUTINA,VESPERTINA,NOCTURNA' })
    },
    onError: (e) => showRpcError(e, 'No se pudo guardar la lotería'),
  })

  // La RPC es un upsert completo: para sólo cambiar el estado hay que mandar
  // la fila entera con el nuevo is_active.
  async function toggle(ds) {
    try {
      await callRpc('admin_draw_source_upsert', {
        p_payload: {
          code: ds.code,
          name: ds.name,
          kind: ds.kind,
          jurisdiction: ds.jurisdiction,
          shifts: ds.shifts,
          timezone: ds.timezone,
          is_active: !ds.is_active,
          sort_order: ds.sort_order,
        },
      })
      invalidate()
    } catch (e) {
      showRpcError(e, 'No se pudo cambiar el estado')
    }
  }

  function onSubmit(e) {
    e.preventDefault()
    setError(null)
    const code = form.code.trim().toUpperCase().replace(/[^A-Z0-9_]/g, '')
    if (!/^[A-Z0-9_]{3,40}$/.test(code)) {
      return setError('El código: 3 a 40 caracteres, mayúsculas, números y guión bajo.')
    }
    if (form.name.trim().length < 3) return setError('Poné un nombre para la lotería.')
    const shifts = form.shifts
      .split(',')
      .map((s) => s.trim().toUpperCase().replace(/[^A-Z0-9_]/g, ''))
      .filter(Boolean)
    save.mutate({
      code,
      name: form.name.trim(),
      kind: form.kind,
      jurisdiction: form.jurisdiction.trim() || null,
      shifts: shifts.length ? shifts : ['UNICA'],
      is_active: true,
    })
  }

  return (
    <Card>
      <CardHeader
        title="Loterías de referencia"
        subtitle="Las activas son las que el comercio puede elegir al armar un evento."
        action={
          <Button variant={adding ? 'secondary' : 'primary'} size="sm" onClick={() => setAdding((a) => !a)}>
            {adding ? 'Cancelar' : '+ Nueva lotería'}
          </Button>
        }
      />

      {isLoading ? (
        <LoadingState />
      ) : (
        <ul className="divide-y divide-ink-100">
          {(sources || []).map((ds) => (
            <li key={ds.id} className="flex items-center justify-between gap-3 py-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <p className="truncate font-medium text-ink-900">{ds.name}</p>
                  <Badge tone={ds.is_active ? 'available' : 'neutral'}>
                    {ds.is_active ? 'Activa' : 'Inactiva'}
                  </Badge>
                </div>
                <p className="mt-0.5 text-sm text-ink-500">
                  {KIND_LABEL[ds.kind] ?? ds.kind}
                  {ds.jurisdiction ? ` · ${ds.jurisdiction}` : ''}
                  {ds.shifts?.length ? ` · ${(ds.shifts || []).join(', ')}` : ''}
                </p>
              </div>
              <Button variant="outline" size="sm" onClick={() => toggle(ds)}>
                {ds.is_active ? 'Desactivar' : 'Activar'}
              </Button>
            </li>
          ))}
        </ul>
      )}

      {adding && (
        <AddForm form={form} setForm={setForm} onSubmit={onSubmit} error={error} saving={save.isPending} />
      )}
    </Card>
  )
}

function AddForm({ form, setForm, onSubmit, error, saving }) {
  const selectCls =
    'h-11 rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20'
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }))

  return (
    <form onSubmit={onSubmit} className="mt-4 grid grid-cols-1 gap-4 border-t border-ink-100 pt-4 sm:grid-cols-2">
      <Input
        label="Código (identificador interno)"
        value={form.code}
        onChange={(e) => setForm((f) => ({ ...f, code: e.target.value.toUpperCase() }))}
        placeholder="LOTERIA_DE_CORDOBA"
        hint="Mayúsculas, números y guión bajo."
      />
      <Input label="Nombre visible" value={form.name} onChange={set('name')} placeholder="Lotería de Córdoba" />
      <div className="flex flex-col gap-1.5">
        <label htmlFor="dskind" className="text-sm font-medium text-ink-700">Tipo</label>
        <select id="dskind" value={form.kind} onChange={set('kind')} className={selectCls}>
          {KINDS.map((k) => (
            <option key={k.value} value={k.value}>{k.label}</option>
          ))}
        </select>
      </div>
      <Input label="Jurisdicción (opcional)" value={form.jurisdiction} onChange={set('jurisdiction')} placeholder="AR, Córdoba…" />
      <Input
        label="Turnos (separados por coma)"
        value={form.shifts}
        onChange={set('shifts')}
        placeholder="MATUTINA,VESPERTINA,NOCTURNA"
        hint="Ej: MATUTINA, VESPERTINA, NOCTURNA. Una sola: UNICA."
      />
      {error && <p className="text-sm text-error-500 sm:col-span-2" role="alert">{error}</p>}
      <div className="sm:col-span-2">
        <Button type="submit" loading={saving}>
          Agregar lotería
        </Button>
      </div>
    </form>
  )
}
