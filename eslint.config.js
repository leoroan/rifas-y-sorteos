import js from '@eslint/js'

/*
 * Linter del frontend. La regla que más nos importa es no-undef: Vite NO es un
 * chequeador de tipos, así que un import faltante (ej. usar <Button/> sin
 * importarlo) compila bien y explota en runtime. ESLint lo atrata al instante.
 *
 * Este archivo existe por un bug real: un deploy llegó con "Button is not
 * defined" porque faltaba el import y el build pasó igual.
 */
export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'supabase/**', 'scripts/**'],
  },
  js.configs.recommended,
  {
    files: ['src/**/*.{js,jsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        window: 'readonly',
        document: 'readonly',
        console: 'readonly',
        fetch: 'readonly',
        URL: 'readonly',
        URLSearchParams: 'readonly',
        FormData: 'readonly',
        File: 'readonly',
        Blob: 'readonly',
        alert: 'readonly',
        navigator: 'readonly',
        localStorage: 'readonly',
        sessionStorage: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
      },
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },
    rules: {
      'no-undef': 'error',
      // Los undefined son errores; lo demás, razonable.
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-empty': 'warn',
    },
  },
]
