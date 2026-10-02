import { supabase } from '../client.js'

/* Configuración pública: la que la página del evento necesita mostrar. */
export async function getPublicSettings() {
  const { data, error } = await supabase
    .from('system_settings')
    .select('key, value')
    .eq('is_public', true)
  if (error) throw error
  return Object.fromEntries(data.map((r) => [r.key, r.value]))
}
