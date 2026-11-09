# Descargador: diseño

Fecha: 2026-11-09 · Estado: pendiente de aprobación

## 1. Intención

App de iOS **solo para el iPhone del autor** (iOS 17.6.1) que descarga videos de YouTube,
Instagram, TikTok, X y Facebook al estilo de SnapTube. Todo ocurre dentro del iPhone, sin servidor.
No va a la App Store: se compila gratis en GitHub Actions y se instala con SideStore (o AltStore)
con un Apple ID gratuito.

Por qué así: el autor no tiene Mac ni presupuesto. GitHub Actions da runners macOS gratis en
repositorios públicos, y yt-dlp es el extractor más mantenido. Embeberlo permite actualizarlo sin
recompilar cuando una plataforma cambia.

## 2. Objetivos, no-objetivos y anti-objetivos

**Objetivos**
- Pegar o compartir un enlace, ver miniatura, título, duración y tamaño por calidad, y descargar con
  progreso real (bytes, velocidad, tiempo restante).
- Video final compatible con Fotos (H.264/HEVC + AAC en MP4) sin ffmpeg; audio suelto en Archivos.
- Actualizar yt-dlp desde la propia app.
- Diagnóstico remoto sin Mac: pantalla de Registro copiable y capturas del simulador en cada build.

**No-objetivos** (fuera de este trabajo)
- App Store, iPad optimizado, listas de reproducción, directos, subtítulos, recodificar VP9/AV1.
- Varias descargas simultáneas (**decisión de Claude**: una a la vez; analizar otro enlace sí se
  puede mientras descarga).

**Anti-objetivos** (fracaso aunque "funcione")
- Requerir cuenta de desarrollador de pago, servidor propio o un Mac.
- Fallar en silencio: todo error termina en un mensaje en español y en el Registro.
- Un pipeline en el que un error de compilación sea difícil de encontrar en los logs.

## 3. Restricciones

| Restricción | Consecuencia |
|---|---|
| Sin Mac, sin Swift local | Cada prueba de compilación es una ejecución de Actions (~5-10 min). Código Swift conservador (modo Swift 5, APIs de iOS 16). |
| Apple ID gratuito | Firma de 7 días, 3 apps activas (SideStore ocupa una), 10 App IDs por semana. La Share Extension gasta un App ID extra. Sin push, iCloud ni App Groups. |
| iOS 17.6.1 | No existe `BGContinuedProcessingTask` (iOS 26). `beginBackgroundTask` da ~30 s. |
| iOS sin JIT para apps de terceros | JavaScriptCore dentro de la app funciona solo en modo intérprete (más lento). |
| iOS prohíbe lanzar procesos | yt-dlp no puede ejecutar `deno`/`node`/`quickjs`: hace falta un proveedor JS propio. |
| Repositorio público | Nada de secretos. Las cookies del usuario nunca van al repo. |

## 4. Versiones verificadas (2026-11-09)

| Herramienta | Versión | Nota |
|---|---|---|
| Runner | `macos-26` (Xcode 26.6 por defecto) | `macos-15` tiene simuladores iOS 18.5 |
| XcodeGen | 2.46.0 (16-jul-2026) | se descarga `xcodegen.zip` fijado |
| Python para iOS | BeeWare Python-Apple-support **3.14-b14** (Python 3.14.10, OpenSSL 3.5.9) | python.org publica XCframework oficial solo desde 3.15 (3.15.2) |
| yt-dlp | 2026.10.26 | exige `yt-dlp-ejs==0.8.0`; ya contempla `sys_platform == "ios"` |
| yt-dlp-ejs | 0.8.0 | scripts JS del solucionador de YouTube |
| actions/checkout / upload-artifact | v7 / v7 | |
| SideStore | 0.7.0-alpha (0.6.4 marcada como "no usar") | |
| AltStore | 2.3 | |

## 5. Enfoques considerados

### 5.1 Segundo plano (decidido por el autor: **B**)
- **A.** `beginBackgroundTask` + notificación local al cortarse + reanudación automática al volver
  (yt-dlp continúa el `.part`). Simple; la descarga se pausa al salir.
- **B (elegido).** A + interruptor en Ajustes "Mantener activo en segundo plano": reproduce audio
  silencioso (`UIBackgroundModes: audio`, sesión `.playback` con `.mixWithOthers`) solo mientras hay
  una descarga. iOS no suspende la app. Sin entitlements de pago. Coste: batería; una llamada lo
  interrumpe y se reanuda al terminar.
- **C.** Híbrido con `URLSession` en segundo plano. Descartado: YouTube exige descargas por
  trozos, HLS no encaja, y serían dos motores que depurar sin Mac.

### 5.2 Motor JavaScript para YouTube (decidido por Claude, a validar en Etapa 4)
- **JavaScriptCore (`JSContext`) dentro del proceso (elegido).** Funciona en cualquier hilo y con
  la app en segundo plano. Sin JIT: estimado de varios segundos por video.
- **WKWebView oculto (plan B).** Tiene JIT (proceso aparte), pero exige el hilo principal y su
  proceso web se suspende en segundo plano.
- Mecanismo: subclase de `EJSBaseJCP` de yt-dlp que implementa `_run_js_runtime(script) -> stdout`
  y sobrescribe `is_available()`. Es el mismo patrón que usa el plugin `yt-dlp-apple-webkit-jsi`
  (usado en a-Shell). `EJSBaseJCP` es API privada de yt-dlp: si cambia, el aviso en la app es
  "actualiza la app", no solo yt-dlp.

### 5.3 Python
- **BeeWare 3.14-b14 (elegido por Claude).** Python 3.14 lleva un año en producción con Briefcase.
- **Oficial python.org 3.15.2.** Mismo mecanismo de integración; queda como alternativa si la 3.14
  diera problemas. Se elige 3.14 porque 3.15 tiene un mes y no hay Mac para depurar sorpresas.

## 6. Arquitectura

```
SwiftUI (pantallas)  ──►  Modelos @MainActor (DescargaVM, HistorialStore, Ajustes)
                                  │
                     MotorDescargas (cola de 1, cancelar, segundo plano)
                        │                    │                     │
                PuentePython          UnidorMedios (AVFoundation)   Guardado (Fotos/Archivos)
                   │   ▲
     C API (import Python)  callback C con JSON (progreso, logs, JS)
                   ▼   │
        descargador/puente.py ─► yt-dlp ─► proveedor JS ─► MotorJS (JavaScriptCore)
```

### 6.1 Puente Swift ↔ Python
- Swift hace `import Python` (el XCframework trae module map). Inicialización con `PyPreConfig`
  (UTF-8) y `PyConfig` según la guía oficial: sin bytecode, stdio sin búfer, `PYTHONHOME` en
  `python/` del bundle. Rutas en orden de prioridad: `Application Support/yt-dlp/*.whl`
  (actualización), `app_packages`, `app`.
- Interfaz mínima: una función Python `ejecutar(peticion_json, direccion_callback) -> str`.
  El callback es un puntero de función C creado en Swift (`@convention(c)`), envuelto en Python
  con `ctypes.CFUNCTYPE`. Todo viaja como JSON en texto. El callback devuelve `1` para pedir
  cancelación: el progress hook lanza una excepción y yt-dlp se detiene.
- Cada trabajo corre en su propio `Thread` con `PyGILState_Ensure`; tras inicializar se libera el
  GIL. ctypes suelta el GIL al llamar a Swift.
- Reiniciar Python no es fiable: actualizar yt-dlp pide reabrir la app.

### 6.2 Selección de formatos y unión
- Calidades: Mejor, 1080p, 720p, 480p, 360p, Solo audio. "Mejor" = la mejor **compatible con
  Fotos** (normalmente ≤1080p en YouTube; el 4K de YouTube solo existe en VP9/AV1 y se omite,
  explicado en la app).
- Preferencia por calidad: (1) archivo único MP4 con video+audio H.264/HEVC → sin unir;
  (2) video `avc1` MP4 + audio `mp4a` M4A por separado → se descargan como dos trabajos yt-dlp y
  se unen con `AVMutableComposition` + `AVAssetExportSession` passthrough a MP4; (3) HEVC solo si
  el tag es `hvc1`. Tamaños: `filesize` o `filesize_approx` sumando video+audio.
- Solo audio: M4A (AAC) a `Documents/Descargas` (visible en Archivos). MP3 no: requiere
  codificador que iOS no trae.
- Progreso total ponderado por tamaño de cada parte; fase "Uniendo audio y video" con el progreso
  de `AVAssetExportSession`.

### 6.3 Errores
`puente.py` clasifica la excepción y devuelve un código: `privado`, `no_soportado`,
`sin_conexion`, `requiere_sesion` (bot check / login → sugerir cookies), `geo`, `extractor`
(plataforma cambió → sugerir actualizar yt-dlp), `cancelado`, `desconocido`. Swift traduce a
español y guarda el mensaje original en el Registro.

### 6.4 Almacenamiento
- `Documents/Descargas/`: audios y copia de videos (visible en Archivos con
  `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`). **Decisión de Claude:** se guarda
  una copia del video en la app porque el permiso "solo añadir" de Fotos no permite volver a leerlo,
  y el historial necesita reproducir y compartir. "Borrar" en el historial elimina la copia de la
  app (no la de Fotos). Ajustes muestra el espacio usado y un botón "Vaciar descargas".
- `Application Support/`: historial (JSON), miniaturas, `cookies.txt`, wheels actualizados de
  yt-dlp. **Decisión de Claude:** la actualización va aquí y no en `Documents` para que no aparezca
  ni se borre desde Archivos; es igual de persistente.
- `Caches/registro.log`: registro rotativo (≈2000 líneas) que sobrevive a cierres inesperados.

### 6.5 Share Extension y Atajos
- Extensión `com.apple.share-services` que acepta URL o texto (TikTok comparte texto), extrae el
  primer enlace y abre `descargador://download?url=...` recorriendo la cadena de responders hasta
  `UIApplication.open(_:options:completionHandler:)`. Sin App Groups.
- App Intent "Descargar video" (URL + calidad) con `openAppWhenRun = true`: la descarga necesita
  la app en primer plano. `AppShortcutsProvider` con frases en español. Sin entitlements.
- Esquema `descargador://download?url=...&calidad=720` (calidad opcional).

### 6.6 Interfaz
Pestañas: **Descargar**, **Historial**, **Ajustes**, **Registro**. Modo claro/oscuro del sistema
con opción de forzar en Ajustes. Todo en español. Pegar con `PasteButton` (sin alerta de
permiso). Al volver a la app, `UIPasteboard.detectPatterns(.probableWebURL)` detecta un enlace
sin leerlo y ofrece "Usar enlace copiado".

## 7. CI (GitHub Actions)
- **compilar** (`macos-26`): XcodeGen fijado → (desde Etapa 2: Python-Apple-support + wheels puros
  de yt-dlp y dependencias en `app_packages`) → `xcodebuild` para `iphoneos` con
  `CODE_SIGNING_ALLOWED=NO` → `Payload/` → `.ipa` → artifact. En tags `v*`, `gh release create`.
- **simulador** (`macos-15`, iOS 18.x, lo más parecido a iOS 17 que ofrece GitHub): compila para
  simulador y ejecuta UI tests que recorren las pantallas, prueban pegar/analizar y el esquema de
  URL, y guardan capturas en claro y oscuro. Las capturas se extraen del `.xcresult` y se suben
  como artifact.
- Errores legibles: `xcbeautify --renderer github-actions` (anota errores en el PR/commit), log
  completo como artifact si falla, y un resumen con las líneas `error:` en el Step Summary.
- Número de build = `github.run_number`; commit corto en `Info.plist`. Ajustes y Registro lo
  muestran para saber qué build tiene el iPhone.

## 8. Etapas y criterio de "hecho"
1. **Esqueleto + CI.** Pestañas, pegar/detectar enlace, detección de plataforma, esquema de URL,
   Registro copiable, icono. *Hecho:* `.ipa` instalado con SideStore abre y navega; capturas del
   simulador visibles en Actions.
2. **Python + yt-dlp.** *Hecho:* Ajustes muestra versión de Python y yt-dlp; analizar un enlace de
   un sitio sencillo (p. ej. Vimeo o un MP4 directo) devuelve título y formatos.
3. **Descarga real.** Progreso, cancelar, unión AVFoundation, Fotos/Archivos, segundo plano B.
   *Hecho:* un video de Instagram/X/TikTok aparece en Fotos con audio.
4. **YouTube.** Proveedor JavaScriptCore. *Hecho:* un video de YouTube a 720p se descarga y el
   Registro muestra el tiempo de resolución del desafío.
5. **Share Extension, Atajos, historial, ajustes completos, actualizar yt-dlp, cookies.**
   *Hecho:* compartir desde la app de YouTube abre Descargador con el enlace; un atajo descarga.

Cada etapa termina con: qué probar en el iPhone, qué capturas revisar y qué copiar del Registro o de
Actions si falla.

## 9. Riesgos conocidos
- YouTube puede exigir PO Tokens a ciertos clientes; algunos formatos pueden faltar sin cookies.
- JavaScriptCore sin JIT puede ser lento; plan B: WKWebView.
- `EJSBaseJCP` es API privada: una versión nueva de yt-dlp descargada desde Ajustes podría romper
  el proveedor JS. Mitigación: si falla al importar, se avisa y se puede volver a la versión
  incluida.
- La Share Extension consume un App ID; con la cuenta gratuita, si SideStore ofrece quitar las
  extensiones, el esquema de URL y Atajos siguen funcionando.

## 10. Decisiones que quedan para quien construye
Nombres de archivos y tipos, maquetación exacta, textos de la interfaz, identificador del bundle,
formato del historial, detalle de las capturas de los UI tests.
