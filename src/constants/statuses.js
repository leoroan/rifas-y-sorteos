/*
 * ÚNICA fuente de códigos de estado del frontend. Debe coincidir con los enums
 * de la base. Los labels son en español; los códigos en inglés, como en la DB.
 */

export const EVENT_STATUS = {
  DRAFT: 'DRAFT',
  PUBLISHED: 'PUBLISHED',
  OPEN: 'OPEN',
  CLOSED: 'CLOSED',
  DRAWN: 'DRAWN',
  CANCELLED: 'CANCELLED',
}

export const NUMBER_STATUS = {
  AVAILABLE: 'AVAILABLE',
  RESERVED: 'RESERVED',
  PAYMENT_SUBMITTED: 'PAYMENT_SUBMITTED',
  PAID: 'PAID',
  CANCELLED: 'CANCELLED',
  WINNER: 'WINNER',
}

export const RESERVATION_STATUS = {
  PENDING: 'PENDING',
  PAYMENT_SUBMITTED: 'PAYMENT_SUBMITTED',
  APPROVED: 'APPROVED',
  EXPIRED: 'EXPIRED',
  REJECTED: 'REJECTED',
  CANCELLED: 'CANCELLED',
}

export const RECEIPT_STATUS = {
  PENDING: 'PENDING',
  APPROVED: 'APPROVED',
  REJECTED: 'REJECTED',
}

export const NUMBER_STATUS_LABEL = {
  [NUMBER_STATUS.AVAILABLE]: 'Disponible',
  [NUMBER_STATUS.RESERVED]: 'Reservado',
  [NUMBER_STATUS.PAYMENT_SUBMITTED]: 'Pago informado',
  [NUMBER_STATUS.PAID]: 'Pagado',
  [NUMBER_STATUS.CANCELLED]: 'Cancelado',
  [NUMBER_STATUS.WINNER]: 'Ganador',
}

export const RESERVATION_STATUS_LABEL = {
  [RESERVATION_STATUS.PENDING]: 'Pendiente de pago',
  [RESERVATION_STATUS.PAYMENT_SUBMITTED]: 'Comprobante en revisión',
  [RESERVATION_STATUS.APPROVED]: 'Confirmado',
  [RESERVATION_STATUS.EXPIRED]: 'Vencido',
  [RESERVATION_STATUS.REJECTED]: 'Rechazado',
  [RESERVATION_STATUS.CANCELLED]: 'Cancelado',
}
