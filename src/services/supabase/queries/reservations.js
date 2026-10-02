import { supabase } from '../client.js'

/* Mis participaciones: reservas propias (RLS limita a profile_id = yo). */

export async function listMyReservations() {
  const { data, error } = await supabase
    .from('reservations')
    .select('id, event_id, status, number_count, total_amount, currency, reserved_at, expires_at, approved_at, closed_at')
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
}

export async function getMyReservationNumbers(reservationId) {
  const { data, error } = await supabase
    .from('reservation_numbers')
    .select('number, assigned_at, released_at')
    .eq('reservation_id', reservationId)
    .order('number', { ascending: true })
  if (error) throw error
  return data
}
