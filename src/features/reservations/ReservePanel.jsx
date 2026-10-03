import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { getEventNumbers } from '../../services/supabase/queries/events.js'
import { getCurrentTerms } from '../../services/supabase/queries/terms.js'
import { getPublicSettings } from '../../services/supabase/queries/settings.js'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError } from '../../lib/sweetalert.js'
import { NUMBER_STATUS, NUMBER_STATUS_LABEL } from '../../constants/statuses.js'
import { Button } from '../../components/ui/Button.jsx'
import { Card } from '../../components/ui/Card.jsx'
import { Badge } from '../../components/ui/Badge.jsx'

const PAGE = 300

const cellTone = {
  [NUMBER_STATUS.AVAILABLE]: 'border-ink-200 bg-paper-100 text-ink-700 hover:border-accent-400',
  [NUMBER_STATUS.RESERVED]: 'border-reserved-200 bg-reserved-50 text-reserved-700 cursor-not-allowed',
  [NUMBER_STATUS.PAYMENT_SUBMITTED]: 'border-submitted-200 bg-submitted-50 text-submitted-700 cursor-not-allowed',
  [NUMBER_STATUS.PAID]: 'border-paid-200 bg-paid-50 text-paid-700 cursor-not-allowed',
  [NUMBER_STATUS.CANCELLED]: 'border-ink-100 bg-ink-50 text-ink-300 cursor-not-allowed',
  [NUMBER_STATUS.WINNER]: 'border-winner-300 bg-winner-50 text-winner-700 cursor-not-allowed',
}

/*
 * Panel de reserva del participante: grilla de números, selección múltiple,
 * aceptación de términos y reserva atómica. La concurrencia la resuelve la
 * base (compare-and-swap); si un número ya fue tomado, acá sólo se informa.
 */
export function ReservePanel({ event, merchant }) {
  const qc = useQueryClient()
  const { user, isAnonymous } = useAuth()
  // Q1: ver público sin cuenta, pero RESERVAR requiere registro (email).
  // Los anónimos ven números y disponibilidad; para actuar deben registrarse.
  const canReserve = !!user && !isAnonymous

  const [selected, setSelected] = useState(() => new Set())
  const [taken, setTaken] = useState(() => new Set())
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(1)
  const [accepted, setAccepted] = useState(false)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState(null)

  const { data: numbers } = useQuery({
    queryKey: ['event-numbers', event.id],
    queryFn: () => getEventNumbers(event.id),
  })

  const { data: terms } = useQuery({
    queryKey: ['terms', 'TERMS'],
    queryFn: () => getCurrentTerms('TERMS'),
  })

  const { data: settings } = useQuery({
    queryKey: ['public-settings'],
    queryFn: getPublicSettings,
  })

  const maxSel = Number(settings?.['limits.max_numbers_per_reservation'] ?? 20)

  const filtered = useMemo(() => {
    const list = numbers || []
    if (!search.trim()) return list
    const q = search.trim()
    return list.filter((n) => String(n.number).includes(q) || (n.display_code || '').includes(q))
  }, [numbers, search])

  const visible = filtered.slice(0, page * PAGE)
  const selectedList = useMemo(() => [...selected].sort((a, b) => a - b), [selected])
  const total = selected.size * (event.price_per_number || 0)

  function toggle(n) {
    setError(null)
    if (!canReserve) {
      setError('Para reservar números tenés que registrarte o iniciar sesión.')
      return
    }
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(n.number)) {
        next.delete(n.number)
      } else if (next.size < maxSel) {
        next.add(n.number)
      } else {
        setError(`Podés reservar hasta ${maxSel} números por vez.`)
      }
      return next
    })
  }

  async function onReserve() {
    setError(null)
    if (!selected.size) return setError('Elegí al menos un número.')
    if (!terms) return setError('Las condiciones no están disponibles. Probá de nuevo.')
    if (!accepted) return setError('Tenés que aceptar las condiciones para reservar.')

    setBusy(true)
    try {
      await callRpc('terms_accept', {
        p_terms_version_id: terms.id,
        p_event_id: event.id,
      })

      const res = await callRpc('reservation_create', {
        p_event_id: event.id,
        p_numbers: selectedList,
        p_terms_version_id: terms.id,
      })

      setResult(res)
      qc.invalidateQueries({ queryKey: ['event-numbers', event.id] })
      qc.invalidateQueries({ queryKey: ['event-summary', event.id] })
    } catch (e) {
      if (e.code === 'NUMBER_TAKEN' && e.details?.taken) {
        const lost = new Set(e.details.taken)
        setTaken(lost)
        setSelected((prev) => new Set([...prev].filter((n) => !lost.has(n))))
        showRpcError(e)
      } else {
        showRpcError(e, 'No se pudo reservar')
      }
    } finally {
      setBusy(false)
    }
  }

  if (result) {
    return (
      <Card className="border-paid-500/40">
        <div className="flex items-center gap-2">
          <Badge tone="paid">Reserva confirmada</Badge>
          <span className="tnum font-semibold text-ink-900">
            {result.number_count} número(s) · ${result.total_amount} {result.currency}
          </span>
        </div>

        <div className="mt-3 flex flex-wrap gap-2">
          {(result.numbers || []).map((n) => (
            <span key={n} className="tnum rounded-md border border-paid-200 bg-paid-50 px-2.5 py-1 text-sm font-semibold text-paid-700">
              {n}
            </span>
          ))}
        </div>

        <div className="mt-4 space-y-2 text-sm text-ink-600">
          <p>
            Tenés tiempo hasta{' '}
            <strong>{new Date(result.expires_at).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })}</strong>{' '}
            para subir el comprobante de pago.{' '}
            {result.total_amount > 0 ? `Total a pagar: $${result.total_amount} ${result.currency}.` : 'Este sorteo es gratis.'}
          </p>
          {merchant?.payment_instructions && (
            <div className="rounded-md bg-ink-50 p-3 text-ink-700">
              <p className="mb-1 font-medium text-ink-800">Cómo pagar</p>
              <p className="whitespace-pre-line">{merchant.payment_instructions}</p>
            </div>
          )}
          {merchant?.contact_whatsapp && (
            <p>Contacto del comercio: <span className="font-medium text-ink-800">{merchant.contact_whatsapp}</span></p>
          )}
          <p>
            <Link to="/mis-participaciones" className="font-medium text-accent-600">Ver mis participaciones</Link>
          </p>
          {isAnonymous && (
            <p className="rounded-md border border-accent-200 bg-accent-50 p-3 text-accent-900">
              Reservaste sin cuenta.{' '}
              <Link to="/crear-cuenta" className="font-semibold underline">Creá una cuenta</Link>{' '}
              para no perder tus números: conservás todo tu historial.
            </p>
          )}
        </div>
      </Card>
    )
  }

  return (
    <Card>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-lg font-semibold text-ink-900">Elegí tus números</h2>
        <span className="text-sm text-ink-500">
          {selected.size > 0
            ? `${selected.size} de ${maxSel} · $${total}`
            : `Podés elegir hasta ${maxSel}`}
        </span>
      </div>

      <input
        type="search"
        value={search}
        onChange={(e) => { setSearch(e.target.value); setPage(1) }}
        placeholder="Buscar número…"
        aria-label="Buscar número"
        className="mb-3 h-10 w-full rounded-md border border-ink-300 bg-paper-100 px-3 text-ink-900 placeholder:text-ink-400 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20 sm:max-w-xs"
      />

      <div className="grid grid-cols-[repeat(auto-fill,minmax(3.5rem,1fr))] gap-1.5">
        {visible.map((n) => {
          const isSel = selected.has(n.number)
          const available = n.status === NUMBER_STATUS.AVAILABLE
          const isTaken = taken.has(n.number)
          return (
            <button
              key={n.number}
              type="button"
              disabled={!available}
              onClick={() => toggle(n)}
              title={
                (NUMBER_STATUS_LABEL[n.status] ?? n.status) +
                (isTaken ? ' — lo perdiste por otra reserva mas rapida' : '')
              }
              aria-pressed={isSel}
              className={`tnum h-10 rounded-md border text-sm font-semibold transition-colors ${
                isSel
                  ? 'border-accent-600 bg-accent-600 text-white'
                  : cellTone[n.status] ?? 'border-ink-200 bg-paper-100 text-ink-700'
              }`}
            >
              {n.display_code ?? n.number}
            </button>
          )
        })}
      </div>

      {filtered.length > visible.length && (
        <button
          type="button"
          onClick={() => setPage((p) => p + 1)}
          className="mt-3 text-sm font-medium text-accent-600 hover:underline"
        >
          Mostrar más ({filtered.length - visible.length} restantes)
        </button>
      )}

      {!canReserve ? (
        <div className="mt-4 border-t border-ink-100 pt-4">
          <div className="rounded-lg border border-accent-200 bg-accent-50 p-4 text-center">
            <p className="font-semibold text-accent-900">
              Para reservar tus números tenés que registrarte
            </p>
            <p className="mt-1 text-sm text-accent-800">
              Podés ver los números y la disponibilidad sin cuenta, pero para participar necesitás una.
            </p>
            <div className="mt-3 flex justify-center gap-3">
              <Link to="/registrarse">
                <Button size="lg">Registrarme</Button>
              </Link>
              <Link to="/ingresar">
                <Button size="lg" variant="secondary">Ya tengo cuenta</Button>
              </Link>
            </div>
          </div>
        </div>
      ) : (
      <div className="mt-4 border-t border-ink-100 pt-4">
        {terms && (
          <details className="mb-3">
            <summary className="cursor-pointer text-sm font-medium text-ink-700">
              Ver las condiciones del sorteo
            </summary>
            <p className="mt-2 max-h-52 overflow-y-auto whitespace-pre-line rounded-md bg-ink-50 p-3 text-xs text-ink-600">
              {terms.content}
            </p>
          </details>
        )}

        <label className="flex cursor-pointer items-start gap-2 text-sm text-ink-700">
          <input
            type="checkbox"
            checked={accepted}
            onChange={(e) => setAccepted(e.target.checked)}
            className="mt-0.5 h-4 w-4 accent-[#1f4ddb]"
          />
          <span>
            Declaro que leí y acepto las condiciones del sorteo.
            {!user && ' (Podés participar sin crear cuenta.)'}
          </span>
        </label>

        {error && <p className="mt-2 text-sm text-error-500" role="alert">{error}</p>}

        <div className="mt-4 flex flex-wrap items-center gap-3">
          <Button size="lg" onClick={onReserve} loading={busy} disabled={!selected.size}>
            Reservar {selected.size > 0 ? `${selected.size} número(s)` : ''}
          </Button>
          <span className="text-sm text-ink-500">
            {total > 0 ? `Total: $${total} ${event.currency}` : 'Gratis'}
          </span>
        </div>
      </div>
      )}
    </Card>
  )
}
