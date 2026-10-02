import { supabase } from '../client.js'

/*
 * Lecturas públicas de eventos. Usan las VISTAS públicas (que ocultan campos
 * internos) y las policies de RLS. El visitante anónimo lee lo mismo que un
 * registrado: el evento, los premios y la disponibilidad de los números.
 */

export async function listPublicEvents() {
  const { data, error } = await supabase
    .from('public_events')
    .select('*')
    .order('participation_ends_at', { ascending: true })
  if (error) throw error
  return data
}

export async function getPublicEventBySlug(slug) {
  const { data, error } = await supabase
    .from('public_events')
    .select('*')
    .eq('slug', slug)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function getEventPrizes(eventId) {
  const { data, error } = await supabase
    .from('public_prizes')
    .select('*')
    .eq('event_id', eventId)
    .order('position', { ascending: true })
  if (error) throw error
  return data
}

export async function getEventNumbers(eventId, { from = null, to = null, status = null } = {}) {
  let q = supabase
    .from('public_event_numbers')
    .select('number, display_code, status')
    .eq('event_id', eventId)
    .order('number', { ascending: true })
  if (from != null) q = q.gte('number', from)
  if (to != null) q = q.lte('number', to)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data
}

export async function getEventMerchant(eventId) {
  const { data: event, error } = await supabase
    .from('public_events')
    .select('merchant_id')
    .eq('id', eventId)
    .maybeSingle()
  if (error) throw error
  if (!event) return null
  const { data, error: err2 } = await supabase
    .from('public_merchants')
    .select('id, name, slug, logo_path, contact_phone, contact_whatsapp, contact_instagram, payment_instructions')
    .eq('id', event.merchant_id)
    .maybeSingle()
  if (err2) throw err2
  return data
}

export async function getEventNumbersSummary(eventId) {
  const numbers = await getEventNumbers(eventId)
  const byStatus = {}
  for (const n of numbers) byStatus[n.status] = (byStatus[n.status] || 0) + 1
  const total = numbers.length
  return { total, byStatus, available: byStatus.AVAILABLE || 0 }
}
