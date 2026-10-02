import { supabase } from '../client.js'

/* Lecturas del panel del comercio. La RLS acota a los comercios del usuario. */

export async function listMyMerchants() {
  const { data, error } = await supabase
    .from('merchant_members')
    .select('role, status, merchant_id, merchants:merchant_id(id, name, slug, status, currency)')
    .eq('status', 'ACTIVE')
  if (error) throw error
  return (data || [])
    .filter((m) => m.merchants)
    .map((m) => ({ ...m.merchants, memberRole: m.role }))
}

export async function listMerchantEvents(merchantId) {
  const { data, error } = await supabase
    .from('events')
    .select('id, merchant_id, kind, title, slug, status, numbers_from, numbers_to, price_per_number, currency, participation_ends_at, winner_method, numbers_locked_at')
    .eq('merchant_id', merchantId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
}

export async function listEventPrizes(eventId) {
  const { data, error } = await supabase
    .from('prizes')
    .select('id, event_id, position, title, description, estimated_value, currency, status')
    .eq('event_id', eventId)
    .order('position', { ascending: true })
  if (error) throw error
  return data
}

export async function getEventFull(eventId) {
  const { data, error } = await supabase
    .from('events')
    .select('*')
    .eq('id', eventId)
    .maybeSingle()
  if (error) throw error
  return data
}
