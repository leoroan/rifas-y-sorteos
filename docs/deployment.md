# Deployment

## GitHub Pages

La SPA se despliega automáticamente en cada push a main vía GitHub Actions.

URL: https://myselfproductions.me/rifas-y-sorteos/

## Variables (Settings → Secrets and variables → Actions → Variables)

| Nombre | Valor |
|---|---|
| VITE_SUPABASE_URL | https://fwouperxtggwfageypss.supabase.co |
| VITE_SUPABASE_PUBLISHABLE_KEY | (publishable key del proyecto) |
| VITE_PUBLIC_APP_URL | https://myselfproductions.me/rifas-y-sorteos |

## Configuración en GitHub

1. Settings → Pages → Source: **GitHub Actions**
2. Variables creadas arriba
3. Workflow: .github/workflows/deploy.yml (en main)

## Flujo

1. Se hace merge a main
2. GitHub Actions corre: npm ci → lint → build → deploy
3. El bundle se publica en GitHub Pages

## Desarrollo

npm run dev       # desarrollo local
npm run build     # build de producción
npm run lint      # ESLint (no-undef, etc.)
npm run sql:check # valida SQL de migraciones
