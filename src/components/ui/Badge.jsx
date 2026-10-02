const tones = {
  neutral: 'bg-ink-100 text-ink-700',
  accent: 'bg-accent-100 text-accent-800',
  available: 'bg-available-50 text-available-700',
  reserved: 'bg-reserved-50 text-reserved-700',
  submitted: 'bg-submitted-50 text-submitted-700',
  paid: 'bg-paid-50 text-paid-700',
  winner: 'bg-winner-50 text-winner-700',
  error: 'bg-error-50 text-error-700',
  warn: 'bg-warn-50 text-warn-700',
}

/*
 * Badge de estado. El estado NUNCA se comunica sólo con color: siempre lleva
 * texto (y puede llevar un ícono), para ser legible por personas daltónicas.
 */
export function Badge({ tone = 'neutral', children, className = '' }) {
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  )
}
