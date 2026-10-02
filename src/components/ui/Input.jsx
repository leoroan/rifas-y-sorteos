import { forwardRef, useId } from 'react'

/*
 * Input con label accesible y error inline. Los errores de validación van
 * ACÁ (no en SweetAlert, que se reserva para operaciones de negocio).
 */
export const Input = forwardRef(function Input(
  { label, error, hint, id, className = '', type = 'text', ...props },
  ref,
) {
  const autoId = useId()
  const inputId = id || autoId
  const hintId = hint ? `${inputId}-hint` : undefined
  const errorId = error ? `${inputId}-error` : undefined

  return (
    <div className={`flex flex-col gap-1.5 ${className}`}>
      {label ? (
        <label htmlFor={inputId} className="text-sm font-medium text-ink-700">
          {label}
        </label>
      ) : null}
      <input
        ref={ref}
        id={inputId}
        type={type}
        aria-invalid={error ? true : undefined}
        aria-describedby={[errorId, hintId].filter(Boolean).join(' ') || undefined}
        className={`h-11 rounded-md border bg-paper-100 px-3 text-ink-900 placeholder:text-ink-400 transition-colors focus:outline-none focus:border-accent-500 focus:ring-2 focus:ring-accent-500/20 ${
          error ? 'border-error-500' : 'border-ink-300'
        }`}
        {...props}
      />
      {error ? (
        <p id={errorId} className="text-sm text-error-500" role="alert">
          {error}
        </p>
      ) : hint ? (
        <p id={hintId} className="text-sm text-ink-500">
          {hint}
        </p>
      ) : null}
    </div>
  )
})
