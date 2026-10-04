/*
 * Configuración del sitio: marca, copy mutable, footer.
 * Cambiar textos de marca y contenido acá, no en los componentes.
 */

export const site = {
  name: 'rifas y sorteos',
  mark: '#',
  tagline: 'Sorteos claros, transparentes y verificables.',
  description:
    'Publicá tu sorteo, compartí el enlace y olvidate del caos. Los participantes eligen números, suben el comprobante, y vos decidís el ganador — con evidencia y auditoría completa.',
  heroCta: 'Quiero publicar sorteos',
  heroSecondary: 'Explorar sorteos',

  footer: {
    tagline: 'Sorteos simples, claros y auditables.',
    note: 'Los sorteos son responsabilidad de quien los publica.',
    links: [
      { label: 'Términos y condiciones', to: '/terminos' },
      { label: 'Política de privacidad', to: '/privacidad' },
      { label: 'Reglas de participación', to: '/reglas' },
      { label: 'Quiero publicar sorteos', to: '/solicitar' },
    ],
  },
}
