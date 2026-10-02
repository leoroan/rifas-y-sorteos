export function Spinner({ size = 24, className = '' }) {
  return (
    <svg
      className={`animate-spin text-accent-600 ${className}`}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="10" stroke="currentColor" strokeOpacity="0.2" strokeWidth="3" />
      <path d="M22 12a10 10 0 0 0-10-10" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  )
}

export function LoadingState({ label = 'Cargando…' }) {
  return (
    <div className="flex items-center justify-center gap-3 py-16 text-ink-500" role="status" aria-live="polite">
      <Spinner />
      <span className="text-sm">{label}</span>
    </div>
  )
}

export function FullPageLoader({ label = 'Cargando…' }) {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <LoadingState label={label} />
    </div>
  )
}
