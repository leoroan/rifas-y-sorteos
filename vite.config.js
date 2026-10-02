import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  /*
   * base = subpath desde donde se sirve la app.
   *  - GitHub Pages sin dominio custom:  https://USER.github.io/REPO/  ->  '/REPO/'
   *  - Con dominio custom o en dev:      https://dominio.com/          ->  '/'
   * Se define por VITE_BASE_PATH; con fallback al nombre del repo sólo
   * en producción.
   */
  const base =
    env.VITE_BASE_PATH || (mode === 'production' ? '/rifas-y-sorteos/' : '/')

  return {
    base,
    plugins: [react(), tailwindcss()],
    server: { port: 5173 },
    build: {
      outDir: 'dist',
      sourcemap: false,
    },
  }
})
