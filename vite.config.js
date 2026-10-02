import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    // GitHub Pages sirve la app desde un subpath. En dev queda '/'.
    base: env.VITE_BASE_PATH || (mode === 'production' ? '/rifas-y-sorteos/' : '/'),
    plugins: [react(), tailwindcss()],
    server: { port: 5173 },
    build: {
      outDir: 'dist',
      sourcemap: false,
      // No hay ningún secreto en el bundle: sólo variables VITE_* públicas.
    },
  }
})
