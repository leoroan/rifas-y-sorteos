/*
 * ÚNICO punto de acceso a import.meta.env.
 * Si falta una variable, falla ruidosamente al arrancar en lugar de devolver
 * undefined a mitad de un flujo.
 *
 * REGLA: sólo va material PÚBLICO. Nunca service_role ni secretos.
 */

function required(name) {
  const value = import.meta.env[name]
  if (!value) {
    throw new Error(
      `Falta la variable de entorno ${name}. Copiá .env.example a .env y completá los valores del proyecto Supabase.`,
    )
  }
  return value
}

export const env = {
  supabaseUrl: required('VITE_SUPABASE_URL'),
  supabasePublishableKey: required('VITE_SUPABASE_PUBLISHABLE_KEY'),
  appUrl: import.meta.env.VITE_PUBLIC_APP_URL || window.location.origin,
  appName: import.meta.env.VITE_APP_NAME || 'rifas-y-sorteos',
  isDev: import.meta.env.DEV,
}
