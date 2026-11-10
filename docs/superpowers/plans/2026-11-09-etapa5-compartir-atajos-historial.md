# Etapa 5 — Historial, ajustes, cookies, Share Extension y Atajos: plan

> **Para agentes:** ejecutar tarea a tarea; los pasos usan casillas (`- [ ]`).

**Objetivo:** cerrar la especificación: historial de descargas (miniatura, título, tamaño,
fecha; reproducir, compartir, borrar), calidad predeterminada, cookies opcionales
(`cookies.txt`), Descargador en la hoja de Compartir (Share Extension) y la acción
"Descargar video" en Atajos (App Intents).

**Spec:** `docs/superpowers/specs/2026-11-09-descargador-design.md` §6.4, §6.5.

## Decisiones

- **Historial** en `Application Support/historial.json`; archivos en `Documents/Descargas`
  (ya existentes). Miniatura generada del propio video con `AVAssetImageGenerator` (sin red).
  Borrar en el historial borra la copia de la app, nunca la de Fotos. Si el archivo ya no existe
  (borrado desde Archivos), la entrada lo indica y solo se puede quitar.
- **Calidad predeterminada** (`@AppStorage("calidadPredeterminada")`, por defecto "Preguntar"):
  se aplica a los enlaces que llegan por Compartir, Atajos o `descargador://` sin calidad. Si la
  calidad no existe para ese video, se usa la más cercana por debajo.
- **Cookies:** se importan con el selector de archivos a `Application Support/cookies.txt`
  (formato Netscape, validado) y se pasan a yt-dlp como `cookiefile`. Nunca van al Registro.
- **Share Extension** (`com.apple.share-services`, sin storyboard ni App Groups): toma la URL o
  el texto compartido, extrae el enlace y abre `descargador://download?url=…` recorriendo la
  cadena de responders hasta `UIApplication.open`. Comparte `Enlaces.swift` y `Calidad.swift`.
  `APPLICATION_EXTENSION_API_ONLY: NO` para poder llamar a `open` (app no destinada a la App Store).
- **App Intents:** `DescargarVideoIntent` (enlace + calidad, `openAppWhenRun`) deja el enlace en
  un buzón (`BuzonEnlaces`) que `EstadoApp` atiende tanto en arranque en frío como en caliente.

## Foco de revisión

1. Texto compartido con el enlace en medio (TikTok/Instagram) en la extensión. *Test:* `Enlaces.enlaceProfundo` + `peticion(desde:)` ida y vuelta.
2. Calidad predeterminada que no existe para el video. *Test:* `test_opcionMasCercana`.
3. Archivo del historial borrado desde Archivos. *Test:* `test_entradaSinArchivo`.
4. `cookies.txt` mal formado o de otro tipo. *Test:* `test_cookiesInvalidas`.
5. Enlace de Atajos que llega antes de que exista `EstadoApp` (arranque en frío). *Test:* `test_buzonPendienteAlCrearEstado`.

## Tareas

1. Enlaces/Calidad/InfoVideo: `enlaceProfundo(para:calidad:)`, `opcionMasCercana(a:)` + tests.
2. Historial: `EntradaHistorial`, `HistorialStore`, miniaturas, `HistorialView` + tests;
   `GestorDescargas` añade al historial; "Vaciar descargas" también vacía el historial.
3. Ajustes: calidad predeterminada, cookies (importar/borrar) + Python `cookiefile` + tests.
4. Buzón + App Intents + `EstadoApp` (calidad predeterminada) + tests.
5. Share Extension (target XcodeGen) + README (Compartir, Atajos, cookies) + CI verde.
