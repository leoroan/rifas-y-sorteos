# Consideraciones Legales

## Advertencia principal

Un texto de términos y condiciones NO vuelve legal un sorteo.
Las rifas/sorteos pueden estar sujetos a normativa provincial y nacional
y requerir autorizaciones según jurisdicción, modalidad, contraprestación,
premio y mecanismo.

## El sistema

- Cada evento tiene legal_status: PENDING_REVIEW, AUTHORIZED, NOT_AUTHORIZED, EXEMPT, CANCELLED
- El OWNER configura si exige AUTHORIZED para publicar (system_settings: legal.require_authorized_status)
- Los textos legales son versionados (terms_versions) y aceptados con hash (terms_acceptances)
- La aceptación es append-only: no se puede reescribir evidencia

## Responsabilidad

El comercio es responsable del cumplimiento. La plataforma es herramienta.
Esto se refleja en los términos (plantilla 1.0-draft, requiere revisión legal).

## Datos personales

- Se guarda lo mínimo: email, nombre para mostrar, reservas, comprobantes
- IP: nunca cruda, sólo hash con TTL
- Comprobantes en bucket privado, no público
- Derecho de supresión: anonimización (no borrado de auditoría)

## Antes de producción comercial

1. Revisar normativa de cada jurisdicción donde opere el producto
2. Redactar términos con asesoramiento legal
3. Definir política de retención de datos según normativa local
4. Verificar si las rifas requieren autorización previa
