# Etapa 3 — Descarga real, unión y guardado (+ actualizar yt-dlp): plan

> **Para agentes:** ejecutar tarea a tarea; los pasos usan casillas (`- [ ]`).

**Objetivo:** al tocar una calidad empieza la descarga con progreso real (barra, %, MB/MB,
velocidad, tiempo restante), se puede cancelar, se unen audio y video con AVFoundation y el
resultado va a Fotos (video) o a Archivos (audio), con botones Compartir y Abrir. Se mantiene
en segundo plano lo que iOS permite (opción B). Además, Ajustes permite actualizar yt-dlp desde
GitHub sin reinstalar la app (adelantado desde la Etapa 5 a petición del usuario).

**Arquitectura:**
- Python `puente.descargar`: extrae una vez y descarga cada parte (`video`, `audio`) con su
  `format_id` en su propio `YoutubeDL` (`process_ie_result` sobre una copia de la info). Un
  progress hook envía eventos `progreso` (máx. 4 por segundo) y lanza `DownloadCancelled` si el
  callback devuelve 1. Verificado en local con `file://`.
- Swift `GestorDescargas` (`@MainActor`): una descarga a la vez; fases
  `preparando → descargando → uniendo → guardando → terminada | fallida | cancelada`.
- `Medios` (AVFoundation): unir video+audio (passthrough a MP4), extraer audio (M4A),
  normalizar audio (passthrough a M4A).
- `Guardado`: copia en `Documents/Descargas/<título>.mp4|m4a` y, si está activado, en Fotos
  (`PHPhotoLibrary`, permiso "solo añadir").
- `SegundoPlano`: `beginBackgroundTask` + notificación local al expirar/terminar; audio
  silencioso en bucle (`.playback` + `.mixWithOthers`) solo si "Mantener activo" está activado.
- `ActualizadorYtDlp`: API de GitHub → descarga el zipapp `yt-dlp` (~3 MB) y el wheel de
  `yt-dlp-ejs` de la versión que exige, verifica el sha256 (`digest` de la API), los guarda en
  `Application Support/yt-dlp/` y van primero en `sys.path` al reiniciar la app.

**Spec:** `docs/superpowers/specs/2026-11-09-descargador-design.md` §5.1 (opción B), §6.2–6.4.

## Restricciones globales

- Info.plist: `NSPhotoLibraryAddUsageDescription`, `UIBackgroundModes: [audio]`.
- AVFoundation con APIs de iOS 16 (`exportAsynchronously`, `loadTracks`).
- Ajustes nuevos (`@AppStorage`): `guardarEnFotos` (true), `mantenerActivo` (false).
- Carpeta temporal por descarga: `Caches/descargas/<id>-<calidad>/` (permite reanudar `.part`).
- Fuente de actualizaciones: solo GitHub (funciona desde Cuba); sin PyPI.

## Foco de revisión

1. Cancelar en mitad de la descarga deja la app lista para otra. *Test:* Python `test_descargaCancelada`; Swift `test_cancelarVuelveAInactivo`.
2. Audio más corto o más largo que el video al unir. *Test:* `test_unirConAudioMasLargo`.
3. Título con `/`, `:` o emojis como nombre de archivo, y nombres repetidos. *Test:* `test_nombreArchivoSeguro`.
4. Progreso sin tamaño total (solo estimado o desconocido). *Test:* `test_progresoSinTotal`.
5. Actualización de yt-dlp corrupta (sha256 distinto): no se activa. *Test:* `test_digestIncorrectoNoSeInstala`.

---

### Tarea 1: Python — `descargar` e `inspeccionar_paquete`
- [ ] Tests locales: descarga `file://` con progreso y ruta final; cancelación → código `cancelado`;
  `inspeccionar_paquete` lee `__version__` y la versión EJS de un wheel/zipapp.
- [ ] Implementar en `puente.py` (opciones comunes compartidas con `info`).

### Tarea 2: Medios y guardado (Swift)
- [ ] `NombresArchivo.seguro(_:)`, `Medios.unir/extraerAudio/normalizarAudio`, `Guardado`.
- [ ] Tests en simulador con medios generados por `AVAssetWriter` (1 s de video H.264 + AAC).

### Tarea 3: GestorDescargas + segundo plano + interfaz
- [ ] `MotorPython.descargar(…, alProgreso:, cancelado:)`; eventos `progreso` en `CajaEventos`.
- [ ] `GestorDescargas` con analizador/motor inyectables; tests con motor falso.
- [ ] UI: filas de calidad tocables, tarjeta de progreso con fase y Cancelar, resultado con
  Compartir / Abrir (Quick Look) / Ver en Fotos; Ajustes: guardar en Fotos, mantener activo.

### Tarea 4: Actualizar yt-dlp desde Ajustes
- [ ] `ActualizadorYtDlp` (GitHub API, descarga, sha256 con CryptoKit, `activo.json`), rutas
  prioritarias en `MotorPython`, botones Buscar/Instalar/Volver a la incluida.
- [ ] Tests: decodificar la respuesta de la API, digest incorrecto, rutas activas.

### Tarea 5: CI, README y verificación
- [ ] UI tests: captura de la descarga de un `.mp4` local no es posible desde la UI; se cubre con
  tests unitarios. Capturas nuevas: Ajustes con las opciones nuevas.
- [ ] README: qué probar en la Etapa 3.
