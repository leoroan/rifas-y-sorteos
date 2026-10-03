import { HashRouter, Route, Routes } from 'react-router-dom'
import { AppLayout } from '../layout/AppLayout.jsx'
import { RedirectIfLoggedIn, RequireAuth, RequireOwner } from './guards.jsx'
import { FullPageLoader } from '../../components/ui/LoadingState.jsx'
import { useAuth } from '../providers/AuthProvider.jsx'

import { HomePage } from '../../pages/HomePage.jsx'
import { EventPage } from '../../features/events/EventPage.jsx'
import { LoginPage } from '../../features/auth/LoginPage.jsx'
import { RegisterPage } from '../../features/auth/RegisterPage.jsx'
import { RecoverPage } from '../../features/auth/RecoverPage.jsx'
import { ResetPage } from '../../features/auth/ResetPage.jsx'
import { ConvertPage } from '../../features/auth/ConvertPage.jsx'
import { ProfilePage } from '../../features/auth/ProfilePage.jsx'
import { ApplicationForm } from '../../features/admin/ApplicationForm.jsx'
import { NotificationsPage } from '../../features/notifications/NotificationsPage.jsx'
import { MyParticipationsPage } from '../../features/participants/MyParticipationsPage.jsx'
import { PanelPage } from '../../features/merchants/PanelPage.jsx'
import { OwnerPage } from '../../features/admin/OwnerPage.jsx'
import { LegalPage } from '../../pages/LegalPage.jsx'
import { NotFoundPage } from '../../pages/NotFoundPage.jsx'

function Root() {
  const { loading } = useAuth()
  if (loading) return <FullPageLoader />
  return (
    <Routes>
      <Route element={<AppLayout />}>
        {/* Público: sin login, sin registro */}
        <Route path="/" element={<HomePage />} />
        <Route path="/solicitar" element={<ApplicationForm />} />
        <Route path="/e/:slug" element={<EventPage />} />
        <Route path="/e/:slug/resultado" element={<EventPage resultado />} />
        <Route path="/terminos" element={<LegalPage kind="TERMS" />} />
        <Route path="/privacidad" element={<LegalPage kind="PRIVACY" />} />
        <Route path="/reglas" element={<LegalPage kind="PARTICIPATION_RULES" />} />

        {/* Auth: si ya hay sesión, redirigir */}
        <Route element={<RedirectIfLoggedIn />}>
          <Route path="/ingresar" element={<LoginPage />} />
          <Route path="/registrarse" element={<RegisterPage />} />
        </Route>
        <Route path="/recuperar" element={<RecoverPage />} />
        <Route path="/recuperar/nueva" element={<ResetPage />} />
        <Route path="/crear-cuenta" element={<ConvertPage />} />

        {/* Participante */}
        <Route element={<RequireAuth />}>
          <Route path="/mis-participaciones" element={<MyParticipationsPage />} />
          <Route path="/perfil" element={<ProfilePage />} />
          <Route path="/notificaciones" element={<NotificationsPage />} />
          <Route path="/panel" element={<PanelPage />} />
        </Route>

        {/* Owner de la plataforma */}
        <Route element={<RequireOwner />}>
          <Route path="/admin" element={<OwnerPage />} />
        </Route>

        <Route path="/404" element={<NotFoundPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}

export function AppRouter() {
  return (
    <HashRouter>
      <Root />
    </HashRouter>
  )
}
