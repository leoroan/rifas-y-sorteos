import { supabase } from '../client.js'

/* Lecturas del panel OWNER. La RLS da al OWNER lectura total, auditada. */

export async function listMerchants() {
  const { data, error } = await supabase
    .from('merchants')
    .select('id, name, slug, status, currency, created_at')
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
}

export async function findProfileByEmail(email) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, email, display_name, platform_role, status, is_anonymous')
    .ilike('email', email.trim())
    .maybeSingle()
  if (error) throw error
  return data
}

export async function listMerchantMembers(merchantId) {
  const { data, error } = await supabase
    .from('merchant_members')
    .select('id, profile_id, role, status, joined_at, profiles:profile_id(email, display_name)')
    .eq('merchant_id', merchantId)
    .order('joined_at', { ascending: true })
  if (error) throw error
  return data
}

export async function listDrawSources() {
  const { data, error } = await supabase
    .from('draw_sources')
    .select('id, code, name, kind, shifts, is_active')
    .order('sort_order', { ascending: true })
  if (error) throw error
  return data
}

export async function listSystemSettings() {
  const { data, error } = await supabase
    .from('system_settings')
    .select('key, value, value_type, direction, min_value, max_value, description, is_public, editable_by_merchant')
    .order('key', { ascending: true })
  if (error) throw error
  return data
}


export async function listPendingInvites() {
  const { data, error } = await supabase
    .from('merchant_invites')
    .select('id, merchant_id, email, role, status, created_at, merchants:merchant_id(name)')
    .eq('status', 'PENDING')
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
}
