import { supabase } from '../services/supabase/client.js'

/*
 * Envoltura única de las RPC. Devuelve data.data cuando ok, o lanza un
 * RpcError con el code estable que define la base. Así el frontend traduce
 * códigos a mensajes en español sin parsear strings de PostgREST.
 */
export class RpcError extends Error {
  constructor(code, message, details) {
    super(message || code)
    this.name = 'RpcError'
    this.code = code
    this.details = details || null
  }
}

export async function callRpc(name, params = {}) {
  const { data, error } = await supabase.rpc(name, params)
  if (error) {
    throw new RpcError(error.code || 'RPC_ERROR', error.message, error.details)
  }

  // Convención de la base: { ok, data } | { ok:false, code, message, details }
  if (data && typeof data === 'object' && 'ok' in data) {
    if (data.ok) return data.data
    throw new RpcError(data.code || 'RPC_FAILED', data.message, data.details)
  }
  return data
}
