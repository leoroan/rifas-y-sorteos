export function EmptyState({ title, description, action, className = '' }) {
  return (
    <div className={`flex flex-col items-center justify-center rounded-lg border border-dashed border-ink-300 bg-paper-100 px-6 py-14 text-center ${className}`}>
      <h3 className="text-base font-semibold text-ink-800">{title}</h3>
      {description ? <p className="mt-1 max-w-sm text-sm text-ink-500">{description}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  )
}
