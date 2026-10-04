import { supabase } from '../client.js'

/*
 * Actividad completa de un comercio: lo que el OWNER necesita para auditar.
 * Todo lo que se puede sacar del uso del sistema por parte del comercio.
 */
export async function getMerchantActivity(merchantId) {
  const [members, events, receipts, reservations, _winners, prizes] = await Promise.all([
    // Equipo y ultimo acceso
    supabase
      .from('merchant_members')
      .select('id, role, status, joined_at, profiles:profile_id(id, email, display_name, last_seen_at)')
      .eq('merchant_id', merchantId)
      .then(({ data, error }) => { if (error) throw error; return data }),

    // Eventos por tipo y estado
    supabase
      .from('events')
      .select('id, kind, status, title, price_per_number, numbers_from, numbers_to, participation_ends_at, created_at')
      .eq('merchant_id', merchantId)
      .order('created_at', { ascending: false })
      .then(({ data, error }) => { if (error) throw error; return data }),

    // Comprobantes aprobados/rechazados
    supabase
      .from('payment_receipts')
      .select('id, status, created_at')
      .eq('merchant_id', merchantId)
      .then(({ data, error }) => { if (error) throw error; return data }),

    // Reservas con montos
    supabase
      .from('reservations')
      .select('id, event_id, status, total_amount, currency, number_count, profile_id, created_at, approved_at')
      .eq('merchant_id', merchantId)
      .then(({ data, error }) => { if (error) throw error; return data }),

    // Ganadores
    supabase
      .from('event_winners')
      .select('id, event_id, number, position, claim_status, prize:prize_id(title), profile:profile_id(display_name, email)')
      .eq('event_id', '00000000-0000-0000-0000-000000000000')
      .then(({ data, error }) => { if (error) throw error; return data }),

    // Premios del comercio
    supabase
      .from('prizes')
      .select('id, event_id, title, estimated_value, status')
      .then(({ data, error }) => { if (error) throw error; return data }),
  ])

  // Calcular stats
  const eventIds = new Set((events || []).map((e) => e.id))
  const merchantPrizes = (prizes || []).filter((p) => eventIds.has(p.event_id))

  const eventsByStatus = {}
  for (const e of events || []) {
    eventsByStatus[e.status] = (eventsByStatus[e.status] || 0) + 1
  }

  const eventsByKind = {}
  for (const e of events || []) {
    eventsByKind[e.kind] = (eventsByKind[e.kind] || 0) + 1
  }

  // Recaudacion por evento
  const revenueByEvent = {}
  for (const r of reservations || []) {
    if (r.status !== 'APPROVED') continue
    if (!revenueByEvent[r.event_id]) revenueByEvent[r.event_id] = { total: 0, count: 0, currency: r.currency }
    revenueByEvent[r.event_id].total += Number(r.total_amount || 0)
    revenueByEvent[r.event_id].count += r.number_count
  }

  const totalRevenue = Object.values(revenueByEvent).reduce((a, v) => a + v.total, 0)
  const totalNumbersSold = Object.values(revenueByEvent).reduce((a, v) => a + v.count, 0)

  // Participantes únicos
  const uniqueParticipants = new Set((reservations || []).map((r) => r.profile_id)).size

  // Comprobantes
  const receiptsApproved = (receipts || []).filter((r) => r.status === 'APPROVED').length
  const receiptsRejected = (receipts || []).filter((r) => r.status === 'REJECTED').length
  const receiptsPending = (receipts || []).filter((r) => r.status === 'PENDING').length

  // Ultimo acceso del equipo
  const lastSeen = (members || [])
    .map((m) => m.profiles?.last_seen_at)
    .filter(Boolean)
    .sort()
    .pop()

  // Reservas por estado
  const resByStatus = {}
  for (const r of reservations || []) {
    resByStatus[r.status] = (resByStatus[r.status] || 0) + 1
  }

  return {
    members: members || [],
    events: events || [],
    eventsByStatus,
    eventsByKind,
    totalEvents: (events || []).length,
    revenueByEvent,
    totalRevenue,
    totalNumbersSold,
    uniqueParticipants,
    totalReservations: (reservations || []).length,
    resByStatus,
    receiptsApproved,
    receiptsRejected,
    receiptsPending,
    prizesTotal: merchantPrizes.length,
    prizesDelivered: merchantPrizes.filter((p) => p.status === 'DELIVERED').length,
    lastSeen,
    hasActivity: (events || []).length > 0 || (reservations || []).length > 0,
  }
}
