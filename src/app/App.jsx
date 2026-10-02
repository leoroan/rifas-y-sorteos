import { QueryProvider } from './providers/QueryProvider.jsx'
import { AuthProvider } from './providers/AuthProvider.jsx'
import { AppRouter } from './router/AppRouter.jsx'

export default function App() {
  return (
    <QueryProvider>
      <AuthProvider>
        <AppRouter />
      </AuthProvider>
    </QueryProvider>
  )
}
