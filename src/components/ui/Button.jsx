import { forwardRef } from 'react'
import { Spinner } from './LoadingState.jsx'

const variants = {
  primary: 'bg-accent-600 text-white hover:bg-accent-700 active:bg-accent-800 disabled:bg-accent-300',
  secondary: 'bg-ink-100 text-ink-800 hover:bg-ink-200 active:bg-ink-300 disabled:text-ink-400',
  danger: 'bg-error-500 text-white hover:bg-error-700 disabled:bg-error-500/50',
  ghost: 'bg-transparent text-ink-700 hover:bg-ink-100 active:bg-ink-200 disabled:text-ink-400',
  outline: 'bg-paper-100 text-ink-800 border border-ink-300 hover:border-ink-400 hover:bg-ink-50 disabled:text-ink-400',
}

const sizes = {
  sm: 'h-9 px-3 text-sm gap-1.5',
  md: 'h-11 px-5 text-base gap-2',
  lg: 'h-13 px-7 text-lg gap-2.5',
}

/*
 * Botón con estado `loading` que DESHABILITA el doble submit. Las acciones
 * importantes (reservar, aprobar, publicar) son grandes (size lg).
 */
export const Button = forwardRef(function Button(
  { variant = 'primary', size = 'md', loading = false, disabled = false, type = 'button', className = '', children, ...props },
  ref,
) {
  const isDisabled = disabled || loading
  return (
    <button
      ref={ref}
      type={type}
      disabled={isDisabled}
      aria-busy={loading || undefined}
      className={`inline-flex items-center justify-center rounded-md font-semibold transition-colors duration-150 focus-visible:outline-none disabled:cursor-not-allowed ${variants[variant]} ${sizes[size]} ${className}`}
      {...props}
    >
      {loading ? <Spinner size={18} className="text-current" /> : null}
      <span>{children}</span>
    </button>
  )
})
