import { useRef, useState } from 'react'
import { Button } from './Button.jsx'

const ACCEPT = 'image/jpeg,image/png,image/webp,application/pdf'
const MAX_BYTES = 8 * 1024 * 1024 // 8 MB, como el bucket y el CHECK de la base

/*
 * FileUploader: entrada de archivo accesible, con validación de tipo y tamaño
 * ANTES de subir (el bucket y la base vuelven a validar igual). Vista previa
 * para imágenes. No hace la subida: la dispara el padre con onSelect(file).
 */
export function FileUploader({ onSelect, loading = false, label = 'Subir comprobante' }) {
  const inputRef = useRef(null)
  const [error, setError] = useState(null)
  const [preview, setPreview] = useState(null)
  const [fileName, setFileName] = useState('')

  function validate(file) {
    if (!file) return null
    const allowed = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
    if (!allowed.includes(file.type)) {
      return 'Formato no permitido. Se aceptan JPG, PNG, WEBP o PDF.'
    }
    if (file.size > MAX_BYTES) {
      return `El archivo pesa ${(file.size / 1024 / 1024).toFixed(1)} MB. El máximo es 8 MB.`
    }
    return null
  }

  function handleChange(e) {
    setError(null)
    const file = e.target.files?.[0]
    const msg = validate(file)
    if (msg) {
      setError(msg)
      setPreview(null)
      setFileName('')
      if (inputRef.current) inputRef.current.value = ''
      return
    }
    setFileName(file.name)
    if (file.type.startsWith('image/')) {
      const url = URL.createObjectURL(file)
      setPreview(url)
    } else {
      setPreview(null)
    }
    onSelect(file)
  }

  return (
    <div className="flex flex-col gap-2">
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT}
        onChange={handleChange}
        disabled={loading}
        className="hidden"
        aria-label={label}
      />

      {!fileName ? (
        <Button
          type="button"
          variant="outline"
          onClick={() => inputRef.current?.click()}
          loading={loading}
        >
          {loading ? 'Subiendo…' : label}
        </Button>
      ) : (
        <div className="flex items-center gap-3">
          {preview ? (
            <img
              src={preview}
              alt={`Vista previa de ${fileName}`}
              className="h-14 w-14 rounded-md border border-ink-200 object-cover"
            />
          ) : (
            <span className="grid h-14 w-14 place-items-center rounded-md border border-ink-200 bg-ink-50 text-xs font-semibold text-ink-500">
              PDF
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-ink-800">{fileName}</p>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => { setFileName(''); setPreview(null); if (inputRef.current) inputRef.current.value = '' }}
            >
              Cambiar
            </Button>
          </div>
        </div>
      )}

      {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
    </div>
  )
}
