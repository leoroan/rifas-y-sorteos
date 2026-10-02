import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../providers/AuthProvider.jsx'
import { FullPageLoader } from '../../components/ui/LoadingState.jsx'

/*
 * Estos guards sólo deciden qué se RENDERIZA (UX). La seguridad real vive en
 * RLS, constraints y RPC de la base. Un guard que se pase por alto en la UI
 * no abre ningún agujero: la operación de fondo sigue bloqueada en el servidor.
 */

export function RequireAuth() {
  const { user, loading } = useAuth()
  const location = useLocation()
  if (loading) return <FullPageLoader />
  if (!user) return <Navigate to="/ingresar" replace state={{ from: location }} />
  return <Outlet />
}

export function RequireOwner() {
  const { user, loading, isOwner } = useAuth()
  if (loading) return <FullPageLoader />
  if (!user) return <Navigate to="/ingresar" replace />
  if (!isOwner) return <Navigate to="/" replace />
  return <Outlet />
}

export function RedirectIfLoggedIn() {
  const { user, loading, isOwner, isStaff } = useAuth()
  if (loading) return <FullPageLoader />
  if (user) {
    const dest = isOwner ? '/admin' : isStaff ? '/panel' : '/mis-participaciones'
    return <Navigate to={dest} replace />
  }
  return <Outlet />
}
