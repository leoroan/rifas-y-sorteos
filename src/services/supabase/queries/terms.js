import { supabase } from '../client.js'

/* Textos legales vigentes. Lectura pública (hay que leerlas antes de aceptarlas). */

export async function getCurrentTerms(kind) {
  const { data, error } = await supabase
    .from('terms_versions')
    .select('id, kind, version, title, content, content_hash, published_at, is_current')
    .eq('scope', 'GLOBAL')
    .eq('kind', kind)
    .eq('is_current', true)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function listCurrentTerms() {
  const { data, error } = await supabase
    .from('terms_versions')
    .select('id, kind, version, title, is_current')
    .eq('scope', 'GLOBAL')
    .eq('is_current', true)
  if (error) throw error
  return data
}
