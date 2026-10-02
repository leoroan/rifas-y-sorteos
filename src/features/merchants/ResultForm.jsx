import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'

/*
 * Carga del resultado cuando el evento cerro. Como no hay forma de automatizar
 * la lectura de una loteria, el comerciante carga el resultado a mano:
 *  - MANUAL: un numero ganador POR PUESTO (1ro, 2do, 3ro...), segun los premios.
 *  - RANDOM_SEEDED: el sistema sortea entre los pagados (un clic, seed verificable).
 *  - EXTERNAL_LOTTERY: se carga el extracto y el sistema calcula el numero.
 */
export function ResultForm({ event, prizes }) {
  const qc = useQueryClient()
  const active = (prizes || [])
    .filter((p) => p.status === 'ACTIVE')
    .sort((a, b) => a.position - b.position)

  const [numbers, setNumbers] = useState({})
  const [justification, setJustification] = useState('')
  const [evidenceUrl, setEvidenceUrl] = useState('')
  const [extract, setExtract] = useState('')
  const [drawDate, setDrawDate] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  const isManual = event.winner_method === 'MANUAL'
  const isSeeded = event.winner_method === 'RANDOM_SEEDED'
  const isExternal = event.winner_method === 'EXTERNAL_LOTTERY'

  async function run(payload, label) {
    setBusy(true)
    try {
      const rec = await callRpc('event_record_draw_result', {
        p_event_id: event.id,
        p_payload: payload,
      })

      if (rec && rec.next_step === 'PUBLISH_WINNERS') {
        const pub = await callRpc('event_publish_winners', { p_event_id: event.id })
        const sinGanador = pub?.prizes_without_winner?.length
          ? ` (sin ganador: ${pub.prizes_without_winner.join(', ')})`
          : ''
        showSuccess('Resultado publicado', `${pub?.winners_created ?? 0} ganador(es).${sinGanador}`)
      } else {
        showSuccess('Resultado registrado', 'Revisalo y publicalo cuando quieras.')
      }
      qc.invalidateQueries({ queryKey: ['merchant-events', event.merchant_id] })
      qc.invalidateQueries({ queryKey: ['event-prizes-manage', event.id] })
    } catch (e) {
      showRpcError(e, label)
    } finally {
      setBusy(false)
    }
  }

  async function onSubmit(e) {
    e.preventDefault()
    setError(null)

    if (isSeeded) {
      return run({}, 'No se pudo sortear')
    }

    if (isExternal) {
      if (!extract || !drawDate) return setError('Cargá el extracto y la fecha del sorteo.')
      return run({ extract_number: Number(extract), draw_date: drawDate }, 'No se pudo registrar el resultado')
    }

    // MANUAL: un numero por puesto.
    const declared = active.map((p) => Number(numbers[p.id])).filter((n) => Number.isFinite(n) && n > 0)
    if (!declared.length) return setError('Poné al menos un número ganador.')
    if (justification.trim().length < 20) {
      return setError('Contá cómo se determinó el ganador (mínimo 20 caracteres).')
    }
    if (!evidenceUrl.trim()) return setError('Poné un enlace de evidencia (acta, foto o página del sorteo).')

    return run(
      {
        declared_numbers: declared,
        justification: justification.trim(),
        evidence_url: evidenceUrl.trim(),
      },
      'No se pudo registrar el resultado',
    )
  }

  return (
    <Card className="border-accent-200">
      <CardHeader
        title="Cargar resultado"
        subtitle={
          isSeeded
            ? 'El sistema elige entre los números pagados, con seed verificable.'
            : isExternal
              ? 'Cargá el extracto de la lotería y el sistema calcula el número.'
              : 'Poné el número ganador de cada puesto, según los premios.'
        }
      />

      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        {isSeeded && (
          <p className="text-sm text-ink-600">\            Se sortea <strong>entre los números con pago confirmado</strong>. El número elegido y el seed quedan
            publicados para que cualquiera pueda verificarlo.
          </p>
        )}

        {isExternal && (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Input
              label="Extracto de la lotería"
              type="number"
              value={extract}
              onChange={(e) => setExtract(e.target.value)}
              placeholder="Ej: 4812"
              required
            />
            <Input
              label="Fecha del sorteo de referencia"
              type="date"
              value={drawDate}
              onChange={(e) => setDrawDate(e.target.value)}
              required
            />
          </div>
        )}

        {isManual && (
          <>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              {active.map((p) => (
                <Input
                  key={p.id}
                  label={`${p.position}° puesto — "${p.title}"`}
                  type="number"
                  min={event.numbers_from}
                  max={event.numbers_to}
                  value={numbers[p.id] ?? ''}
                  onChange={(e) => setNumbers((n) => ({ ...n, [p.id]: e.target.value }))}
                  placeholder={`${event.numbers_from}–${event.numbers_to}`}
                />
              ))}
            </div>
            <div className="flex flex-col gap-1.5">
              <label htmlFor="just" className="text-sm font-medium text-ink-700">
                Cómo se determinó el ganador
              </label>
              <textarea
                id="just"
                value={justification}
                onChange={(e) => setJustification(e.target.value)}
                rows={3}
                className="rounded-md border border-ink-300 bg-paper-100 px-3 py-2 text-ink-900 focus:border-accent-500 focus:outline-none focus:ring-2 focus:ring-accent-500/20"
                placeholder="Ej: Sorteo presencial en el local, con planilla firmada por los presentes."
              />
              <p className="text-xs text-ink-400">Mínimo 20 caracteres. Queda registrado y auditado.</p>
            </div>
            <Input
              label="Evidencia (enlace)"
              type="url"
              value={evidenceUrl}
              onChange={(e) => setEvidenceUrl(e.target.value)}
              placeholder="https://… (acta, foto, página del sorteo)"
              hint="Obligatorio: queda como evidencia del sorteo."
              required
            />
          </>
        )}

        {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
        <Button type="submit" size="lg" loading={busy} className="self-start">
          {isSeeded ? 'Sortear y publicar' : 'Publicar resultado'}
        </Button>
      </form>
    </Card>
  )
}
