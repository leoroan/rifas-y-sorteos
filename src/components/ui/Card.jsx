export function Card({ children, className = '', padding = 'p-4' }) {
  return (
    <section className={`rounded-lg border border-ink-200 bg-paper-100 shadow-card ${padding} ${className}`}>
      {children}
    </section>
  )
}

export function CardHeader({ title, subtitle, action, className = '' }) {
  return (
    <header className={`mb-3 flex items-start justify-between gap-3 ${className}`}>
      <div>
        <h2 className="text-lg font-semibold text-ink-900">{title}</h2>
        {subtitle ? <p className="mt-0.5 text-sm text-ink-500">{subtitle}</p> : null}
      </div>
      {action}
    </header>
  )
}
