import { useQuery } from '@tanstack/react-query'
import { useAuth } from '../../app/providers/AuthProvider.jsx'
import { supabase } from '../../services/supabase/client.js'

/*
 * Bandeja de notificaciones internas. Son consecuencia de eventos de negocio
 * (reserva, comprobante, resultado, staff), no de acciones de UI.
 */
export function useNotifications() {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['notifications', user?.id],
    enabled: !!user,
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications')
        .select('id, type, title, body, status, created_at, read_at, event_id, reservation_id')
        .order('created_at', { ascending: false })
        .limit(40)
      if (error) throw error
      const unread = (data || []).filter((n) => !n.read_at).length
      return { list: data || [], unread }
    },
  })
}
