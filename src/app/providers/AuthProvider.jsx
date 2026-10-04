import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import { supabase } from '../../services/supabase/client.js'
import { env } from '../config/env.js'

const AuthContext = createContext(null)

/*
 * Fuente única de la sesión. Escucha onAuthStateChange y carga el profile
 * (que es quien tiene platform_role, is_anonymous y status). El JWT no lleva
 * roles: los lee la base en cada carga (ver §9.2 del documento de arquitectura).
 */
export function AuthProvider({ children }) {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [memberships, setMemberships] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let mounted = true
    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return
      setSession(data.session ?? null)
      setLoading(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s)
    })
    return () => {
      mounted = false
      sub.subscription.unsubscribe()
    }
  }, [])

  const userId = session?.user?.id ?? null

  useEffect(() => {
    if (!userId) {
      setProfile(null)
      setMemberships([])
      return
    }
    let cancelled = false

    supabase
      .from('profiles')
      .select('id, display_name, email, is_anonymous, platform_role, status')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data }) => {
        if (!cancelled) setProfile(data ?? null)
      })

    supabase
      .from('merchant_members')
      .select('merchant_id, role, status')
      .eq('status', 'ACTIVE')
      .then(({ data }) => {
        if (!cancelled) setMemberships(data ?? [])
      })

    return () => {
      cancelled = true
    }
  }, [userId])

  const refreshProfile = useCallback(async () => {
    if (!userId) return null
    const { data } = await supabase
      .from('profiles')
      .select('id, display_name, email, is_anonymous, platform_role, status')
      .eq('id', userId)
      .maybeSingle()
    setProfile(data ?? null)

    // También refresca las membresías, para que el menú (Panel/Admin)
    // reaccione sin tener que cerrar sesión y volver a entrar.
    const { data: mm } = await supabase
      .from('merchant_members')
      .select('merchant_id, role, status')
      .eq('status', 'ACTIVE')
    setMemberships(mm ?? [])
    return data
  }, [userId])

  const signInAnonymously = useCallback(async () => {
    const { data, error } = await supabase.auth.signInAnonymously()
    if (error) throw error
    return data
  }, [])

  const signUp = useCallback(async ({ email, password, displayName }) => {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { display_name: displayName } },
    })
    if (error) throw error
    return data
  }, [])

  const signIn = useCallback(async ({ email, password }) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    return data
  }, [])

  const signOut = useCallback(async () => {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
  }, [])

  const resetPassword = useCallback(async (email) => {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${env.appUrl}/#/recuperar/nueva`,
    })
    if (error) throw error
  }, [])

  /*
   * Conversión anónimo → registrado. El UUID NO cambia: el historial del
   * participante (reservas, comprobantes, ganadores) sobrevive entero.
   * Paso 1: vincular el email. Después de confirmarlo, paso 2: setear password.
   */
  const convertToRegistered = useCallback(
    async ({ email }) => {
      const { data, error } = await supabase.auth.updateUser({ email })
      if (error) throw error
      return data
    },
    [],
  )

  const value = {
    session,
    user: session?.user ?? null,
    profile,
    loading,
    isAnonymous: session?.user?.is_anonymous ?? profile?.is_anonymous ?? false,
    isOwner: profile?.platform_role === 'OWNER',
    isMerchant: memberships.some((m) => m.role === 'MERCHANT'),
    isStaff: memberships.length > 0,
    roleLabel:
      profile?.platform_role === 'OWNER'
        ? 'Propietario'
        : memberships.some((m) => m.role === 'MERCHANT')
          ? 'Organizador'
          : memberships.some((m) => m.role === 'COLLABORATOR')
            ? 'Colaborador'
            : 'Participante',
    refreshProfile,
    signInAnonymously,
    signUp,
    signIn,
    signOut,
    resetPassword,
    convertToRegistered,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth debe usarse dentro de <AuthProvider>')
  return ctx
}
