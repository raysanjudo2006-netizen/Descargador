# Etapa 2 — Python + yt-dlp: plan de implementación

> **Para agentes:** ejecutar tarea a tarea; los pasos usan casillas (`- [ ]`).

**Objetivo:** Python 3.14 y yt-dlp dentro de la app. "Analizar enlace" devuelve miniatura, título,
autor, duración y las calidades (Mejor, 1080p, 720p, 480p, 360p, Solo audio) con su tamaño.
Ajustes muestra las versiones de Python y yt-dlp. La descarga sigue pendiente (Etapa 3).

**Arquitectura:** puente en C (`PuentePython.c`) con tres funciones planas que Swift llama por un
bridging header; el C API de Python solo vive en C. Python expone `descargador.puente` con
funciones `f(peticion_json, direccion_callback, contexto) -> str JSON`. Los eventos (logs y, en la
Etapa 3, progreso) vuelven a Swift por un callback C. La selección de formatos y la
clasificación de errores son Python puro, probado en Windows.

**Stack:** BeeWare Python-Apple-support `3.14-b14` (Python 3.14.10, sha256 `703ff822…c1ee`),
yt-dlp `2026.10.26`, yt-dlp-ejs `0.8.0`, `actions/setup-python@v7`.

**Spec:** `docs/superpowers/specs/2026-11-09-descargador-design.md` (§6.1, §6.2, §6.3)

## Restricciones globales

- Solo wheels `py3-none-any` (pip `--platform any --implementation py --abi none --no-compile`).
- Sin `pycryptodomex` ni `brotli` (binarios; yt-dlp tiene alternativas en Python puro).
- Se eliminan del bundle: `test`, `idlelib`, `tkinter`, `turtledemo`, `ensurepip`, `pydoc_data`,
  `__phello__` y los módulos `_test*.so`/`xx*.so` (≈38 MB).
- `utils.sh` de BeeWare firma cada módulo: si `EXPANDED_CODE_SIGN_IDENTITY` está vacío se usa `-`.
- Hilos de Python con pila de 8 MB; Python se inicializa en un hilo propio que no termina.
- Las descargas grandes en el PC del usuario se evitan (conexión cara): las pruebas locales usan
  los wheels ya descargados.

## Foco de revisión

1. Video vertical (1080×1920): la calidad usa el lado corto. *Test:* `test_verticalUsaLadoCorto`.
2. Formatos sin códecs ni altura (MP4 directo): solo "Mejor" disponible. *Test:* `test_mp4DirectoSinMetadatos`.
3. Solo existen formatos VP9/AV1/HEVC `hev1`: no se ofrecen. *Test:* `test_codecsIncompatiblesSeDescartan`.
4. Error de red dentro de "Unable to download webpage": se clasifica como `sin_conexion`. *Test:* `test_redAntesQueExtractor`.
5. El usuario cambia el enlace mientras se analiza el anterior: el resultado viejo no pisa al nuevo. *Test:* `test_resultadoViejoNoPisaAlNuevo`.

---

### Tarea 1: Lógica Python (selección de formatos, errores, puente) con tests locales

**Archivos:** `App/python/app/descargador/{__init__,seleccion,errores,puente}.py`,
`App/python/tests/{test_seleccion,test_errores,test_puente}.py`, `scripts/probar_python.py`,
`python/requisitos-ios.txt`.

**Interfaces (Python):**
- `seleccion.opciones(info: dict) -> list[dict]` — una entrada por calidad en orden
  `mejor, 1080, 720, 480, 360, audio` con claves `calidad, disponible, resolucion, video, audio,
  unir, bytes, aproximado, protocolo, extraer_audio`.
- `errores.clasificar(mensaje: str) -> str` — `sin_conexion | privado | requiere_sesion | geo |
  no_disponible | no_soportado | extractor | desconocido` (en ese orden de prioridad).
- `puente.version(peticion_json, cb, ctx) -> str` → `{"ok":true,"datos":{"python","yt_dlp","yt_dlp_ejs"}}`.
- `puente.info(peticion_json, cb, ctx) -> str` con petición `{"url","cache","permitir_archivos"}` →
  `{"ok":true,"datos":{id,titulo,autor,duracion,miniatura,extractor,url_pagina,opciones,avisos}}`
  o `{"ok":false,"error":{codigo,mensaje,detalle}}`.
- Eventos al callback: `{"tipo":"log","nivel":"depuracion|info|aviso|error","mensaje":…}`; el
  callback devuelve 1 para cancelar.

- [ ] Tests de selección: avc1+m4a por separado se unen; progresivo preferido a igual resolución;
  vertical usa lado corto; https antes que m3u8; sin códecs ni altura → solo "mejor"; VP9/AV1/hev1
  descartados; tamaño estimado con `tbr × duración` marca `aproximado`; audio sin pista suelta →
  `extraer_audio`.
- [ ] Tests de errores (mensajes reales de yt-dlp, red antes que extractor).
- [ ] Test de puente: `info` de un `file://…/muestra.mp4` con `permitir_archivos` devuelve título
  `muestra` y emite logs por un callback ctypes real; `version` devuelve las versiones.
- [ ] Implementar; `python scripts/probar_python.py` en verde con los wheels locales.

### Tarea 2: Integración en Xcode y CI

**Archivos:** `scripts/ci/preparar_python.sh`, `scripts/instalar_python_en_app.sh`, `project.yml`,
`.github/workflows/build.yml`, `scripts/verificar.py`.

- [ ] `preparar_python.sh`: descarga el tarball, verifica sha256, extrae `Python.xcframework`, instala
  `requisitos-ios.txt` en `App/python/app_packages`, borra `bin/` y `share/`.
- [ ] `instalar_python_en_app.sh` (fase de compilación): `install_stdlib`, poda, `process_dylibs`,
  copia `app` y `app_packages` a `<bundle>/python/`.
- [ ] `project.yml`: dependencia `Python.xcframework` (embebida), bridging header,
  `CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER: NO`, `postBuildScripts` sin análisis de dependencias.
- [ ] Workflow: `setup-python@v7` (3.14) + `preparar_python.sh` en ambos jobs; job `python`
  (ubuntu) que ejecuta `scripts/probar_python.py`.

### Tarea 3: Puente C + MotorPython en Swift

**Archivos:** `App/Sources/Python/{PuentePython.h,PuentePython.c,Descargador-Bridging-Header.h,MotorPython.swift}`,
`App/Sources/Nucleo/{InfoVideo.swift,ErrorMotor.swift}`, `Tests/Unitarias/{InfoVideoTests,MotorPythonTests}.swift`.

**Interfaces:**
- C: `int dp_iniciar(const char *home, const char *rutas /* separadas por \n */, char *error, size_t tam)`;
  `char *dp_llamar(const char *funcion, const char *peticion_json, dp_callback cb, void *contexto)`;
  `void dp_liberar(char *)`; `typedef int (*dp_callback)(const char *evento_json, void *contexto)`.
- Swift: `protocol AnalizadorVideo { func analizar(_ url: URL) async throws -> InfoVideo }`;
  `final class MotorPython: AnalizadorVideo` con `static let compartido`, `version() async throws -> VersionesMotor`,
  `info(url: URL, permitirArchivos: Bool) async throws -> InfoVideo`.
- `struct ErrorMotor: Error { codigo, mensaje, detalle; var mensajeUsuario: String }` (textos §6.3).

- [ ] Tests: decodificar un JSON de ejemplo de `info`; `MotorPythonTests` (en simulador): versión
  `3.14.x` y yt-dlp `2026.10.26`; `info` de un `.mp4` local devuelve "Mejor" disponible.
- [ ] Implementar C, Swift y textos de error.

### Tarea 4: Interfaz del análisis y Ajustes

**Archivos:** `App/Sources/App/EstadoApp.swift`, `App/Sources/Pantallas/Descargar/{DescargarView,TarjetaVideo,ListaCalidades}.swift`,
`App/Sources/Pantallas/Ajustes/AjustesView.swift`, `Tests/Unitarias/EstadoAppTests.swift`.

- [ ] `EstadoApp`: `enum EstadoAnalisis { inactivo, analizando, listo(InfoVideo), fallo(String) }`,
  inyección de `AnalizadorVideo`, cancelación al editar el enlace, `esperarAnalisis()` para tests.
- [ ] Tests con analizador falso: éxito publica la info; fallo publica el mensaje en español;
  resultado viejo no pisa al nuevo.
- [ ] Vistas: miniatura, título, autor · duración, lista de calidades con tamaño (desactivadas,
  nota "La descarga llega en la Etapa 3"), estado "Analizando…" y "Reintentar".
- [ ] Ajustes › Motor de descarga: versiones reales o el error.
- [ ] README: estado de etapas y qué probar en la Etapa 2.
