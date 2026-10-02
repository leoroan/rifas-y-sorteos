import Swal from 'sweetalert2'
import { RpcError } from './rpc.js'

/*
 * SweetAlert2 con disciplina:
 *   - confirmDanger: acciones destructivas (cancelar evento, rechazar pago).
 *   - showRpcError:  errores de RPC con code conocido -> mensaje en español.
 *   - showSuccess:   éxitos de operaciones críticas.
 * NO usar para validación de formularios ni para estados de carga.
 */

const base = {
  confirmButtonText: 'Aceptar',
  buttonsStyling: true,
}

// Mensajes por código de RPC. Fallback: el message que devuelve la base.
const RPC_MESSAGES = {
  AUTH_REQUIRED: 'Necesitás iniciar sesión o continuar como invitado.',
  ACCOUNT_BLOCKED: 'Tu cuenta no está habilitada.',
  BLOCKED: 'No podés participar en este momento.',
  EVENT_CLOSED: 'El plazo de participación ya venció.',
  EVENT_NOT_OPEN: 'El evento no está abierto.',
  EVENT_NOT_STARTED: 'La participación todavía no empezó.',
  EVENT_UNAVAILABLE: 'El evento no está disponible.',
  STAFF_CANNOT_PARTICIPATE: 'Quienes trabajan en este comercio no pueden participar en sus propios sorteos.',
  TERMS_NOT_ACCEPTED: 'Tenés que aceptar las condiciones para reservar.',
  TERMS_VERSION_INVALID: 'Las condiciones cambiaron. Volvé a leerlas y aceptalas.',
  LIMIT_EXCEEDED: 'Superaste la cantidad máxima de números por reserva.',
  EVENT_LIMIT_EXCEEDED: 'Llegaste al máximo de números para este sorteo.',
  TOO_MANY_OPEN: 'Tenés demasiadas reservas abiertas. Completá o cancelá alguna.',
  COOLDOWN_ACTIVE: 'No podés reservar en este momento. Probá más tarde.',
  RATE_LIMITED: 'Estás reservando muy rápido. Probá más tarde.',
  NUMBER_TAKEN: 'Alguno de los números ya no está disponible.',
  INVALID_NUMBERS: 'La selección de números no es válida.',
  FORBIDDEN: 'No tenés permiso para esta acción.',
  NOT_FOUND: 'No se encontró lo que buscabas.',
  ALREADY_DRAWN: 'Este evento ya tiene un resultado registrado.',
  WINNER_NOT_PAID: 'El número sorteado no tiene pago confirmado.',
  RECEIPT_ALREADY_PENDING: 'Ya hay un comprobante en revisión para esta reserva.',
  INVALID_STATE: 'La operación no se puede hacer en el estado actual.',
  SETTING_EXCEEDS_GLOBAL_LIMIT: 'El valor supera el máximo permitido por la plataforma.',
  PERMISSION_ABOVE_CEILING: 'Ese permiso no es delegable.',
}

export function showRpcError(error, fallbackTitle = 'No se pudo completar') {
  const isRpc = error instanceof RpcError || error?.code
  const title = isRpc && RPC_MESSAGES[error.code] ? RPC_MESSAGES[error.code] : error?.message || fallbackTitle
  return Swal.fire({
    ...base,
    icon: 'error',
    title,
    text: isRpc && error.details ? `Código: ${error.code}` : undefined,
  })
}

export function showSuccess(title, text) {
  return Swal.fire({ ...base, icon: 'success', title, text, timer: 2400, showConfirmButton: false })
}

export async function confirmDanger({ title, text, confirmText = 'Confirmar', cancelText = 'Cancelar' }) {
  const res = await Swal.fire({
    icon: 'warning',
    title,
    text,
    showCancelButton: true,
    confirmButtonText: confirmText,
    cancelButtonText: cancelText,
    confirmButtonColor: '#dd3a3a',
  })
  return res.isConfirmed
}
