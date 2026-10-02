import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { callRpc } from '../../lib/rpc.js'
import { showRpcError, showSuccess } from '../../lib/sweetalert.js'
import { Card, CardHeader } from '../../components/ui/Card.jsx'
import { Button } from '../../components/ui/Button.jsx'
import { Input } from '../../components/ui/Input.jsx'

export const slugify = (s) =>
  s.toLowerCase().trim().replace(/[^a-z0-9\s-]/g, '').replace(/[\s_]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '').slice(0, 40)

export function CreateMerchantCard() {
  const qc = useQueryClient()
  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [error, setError] = useState(null)

  const mutation = useMutation({
    mutationFn: (payload) => callRpc('admin_merchant_create', { p_payload: payload }),
    onSuccess: () => {
      showSuccess('Comercio creado', 'Ahora podés asignarle un comerciante.')
      setName('')
      setSlug('')
      qc.invalidateQueries({ queryKey: ['merchants'] })
    },
    onError: (e) => showRpcError(e, 'No se pudo crear el comercio'),
  })

  function onSubmit(e) {
    e.preventDefault()
    setError(null)
    if (name.trim().length < 2) return setError('El nombre es muy corto.')
    if (!/^[a-z0-9]([a-z0-9-]{1,38})[a-z0-9]$/.test(slug)) {
      return setError('El identificador tiene que ser minúsculas, números y guiones (3-40).')
    }
    mutation.mutate({ name: name.trim(), slug })
  }

  return (
    <Card>
      <CardHeader title="Crear comercio" subtitle="Un comercio es un negocio que publica sorteos." />
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        <Input
          label="Nombre del comercio"
          value={name}
          onChange={(e) => { setName(e.target.value); setSlug(slugify(e.target.value)) }}
          placeholder="Almacén Don Pedro"
          required
        />
        <Input
          label="Identificador (va en la URL)"
          value={slug}
          onChange={(e) => setSlug(e.target.value.toLowerCase())}
          placeholder="almacen-don-pedro"
          hint="Minúsculas, números y guiones."
          required
        />
        {error && <p className="text-sm text-error-500" role="alert">{error}</p>}
        <Button type="submit" loading={mutation.isPending} className="self-start">
          Crear comercio
        </Button>
      </form>
    </Card>
  )
}
