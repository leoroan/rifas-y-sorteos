import { createClient } from '@supabase/supabase-js'
import { env } from '../../app/config/env.js'

/*
 * Cliente único. Usa la publishable key (pública por diseño) y persiste la
 * sesión localmente. NUNCA recibe service_role ni secretos.
 */
export const supabase = createClient(env.supabaseUrl, env.supabasePublishableKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    storage: window.localStorage,
    storageKey: 'rifasysorteos.auth',
  },
})
