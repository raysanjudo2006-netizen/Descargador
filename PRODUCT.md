# Product
<!-- impeccable:product-schema 1 -->

> Inferido de la especificación del autor (2026-11-09) y del diseño aprobado en
> `docs/superpowers/specs/2026-11-09-descargador-design.md`; no hubo entrevista aparte.

## Platform
ios

## Users
Una sola persona: el autor, en su iPhone (iOS 17.6.1). Ve un video en YouTube, Instagram, TikTok,
X o Facebook y lo quiere guardado en Fotos (o el audio en Archivos) con el menor número de toques.

## Product Purpose
Descargar videos dentro del propio iPhone, sin servidor, con progreso real y errores claros en
español. Éxito: compartir o pegar un enlace y tener el video en Fotos con audio.

## Positioning
App personal instalada con SideStore; yt-dlp embebido y actualizable desde la app sin recompilar.

## Operating Context
- Entrada: pegar el enlace, el aviso de enlace copiado, la Share Extension, Atajos o `descargador://`.
- Uso con una mano, a menudo justo después de copiar un enlace en otra app.
- Diagnóstico sin Mac: la pestaña Registro se copia y se pega en el chat.

## Capabilities and Constraints
- Apple ID gratuito: firma de 7 días, sin push, iCloud ni App Groups.
- Sin ffmpeg: unión de audio y video con AVFoundation (H.264/HEVC + AAC).
- Toda la interfaz en español; modo claro y oscuro.

## Brand Commitments
Nombre "Descargador". Color de acento coral (#E8442F claro / #FF6B4A oscuro). Icono: flecha
blanca hacia una bandeja sobre degradado naranja-coral. Sin logotipos de terceros.

## Product Principles
1. Un toque menos gana: lo copiado se ofrece solo, la descarga empieza al elegir la calidad.
2. Nativo antes que propio: controles y patrones del sistema.
3. Cada fallo dice qué pasó y qué hacer, y deja rastro en el Registro.
