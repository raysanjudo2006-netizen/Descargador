# Etapa 1 — Esqueleto + CI: plan de implementación

> **Para agentes:** ejecutar tarea a tarea; los pasos usan casillas (`- [ ]`).

**Objetivo:** una app SwiftUI instalable con SideStore (pestañas, pegar/detectar enlace, detección de
plataforma, esquema `descargador://`, Registro copiable) que GitHub Actions compila como `.ipa` sin
firmar y prueba en un simulador iOS 18 con capturas.

**Arquitectura:** proyecto generado con XcodeGen. Lógica pura en `App/Sources/Nucleo` (probada con
XCTest), estado en `EstadoApp` (`@MainActor ObservableObject`), vistas en `App/Sources/Pantallas`.
Dos jobs de CI: `compilar` (macos-26, iphoneos, `.ipa`) y `simulador` (macos-15, tests + capturas).

**Stack:** Swift 5 (modo de lenguaje) + SwiftUI, iOS 16+, XcodeGen 2.46.0, Xcode 26.x, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-11-09-descargador-design.md`

**Sin Mac:** no hay compilador Swift local. Los pasos "verificar en CI" los comprueba el usuario al
hacer push; localmente solo se ejecuta `python scripts/verificar.py` (YAML, JSON, icono, llaves
balanceadas en `.swift`).

## Restricciones globales

- Deployment target iOS `16.0`; `SWIFT_VERSION: "5.0"`; sin paquetes Swift de terceros.
- Bundle ID `com.personal.descargador`; nombre visible `Descargador`; esquema `descargador`.
- Toda la interfaz en español; comentarios del código en español.
- CI: `macos-26` (compilar), `macos-15` + Xcode 26.3 + simulador iPhone con iOS 18.x (probar).
- `actions/checkout@v7`, `actions/upload-artifact@v7`, XcodeGen `2.46.0` desde `xcodegen.zip`.
- Repo público: ningún secreto; `GITHUB_TOKEN` solo para el release.
- Número de build = `github.run_number`; commit corto en la clave `DescargadorCommit` del Info.plist.

## Foco de revisión

1. Texto compartido con palabras, emojis y hashtags alrededor del enlace (TikTok) → se extrae el
   primer enlace http(s). *Test:* Tarea 2, `test_extraeEnlaceDeTextoCompartidoDeTikTok`.
2. Enlace profundo con la URL interna **sin codificar** que trae sus propios `&` (YouTube `&t=10`) →
   se conserva entera. *Test:* Tarea 2, `test_peticionConUrlSinCodificar*`.
3. Hosts con mayúsculas, subdominios (`m.`, `music.`, `vm.`) o trampas de sufijo
   (`notyoutube.com`, `youtube.com.evil.net`). *Test:* Tarea 2, `PlataformaTests`.
4. Archivo de registro con una línea a medio escribir tras un cierre inesperado → carga el resto
   sin fallar. *Test:* Tarea 2, `test_lineaCorruptaSeIgnora`.
5. Portapapeles con el mismo enlace ya ofrecido → el aviso no se repite en cada regreso a la app.
   *Test:* Tarea 4, `test_bannerPortapapelesNoSeRepite`.

---

### Tarea 1: Proyecto base que compila y CI que produce el `.ipa`

**Archivos:**
- Crear: `.gitignore` (ignora `*.xcodeproj`, `App/Info.plist`, `build/`, `DerivedData/`, `.DS_Store`)
- Crear: `project.yml`
- Crear: `App/Sources/App/DescargadorApp.swift` (vista provisional "Descargador"; se sustituye en Tarea 3)
- Crear: `App/Sources/App/InfoBuild.swift`
- Crear: `App/Resources/Assets.xcassets/{Contents.json, AppIcon.appiconset/{Contents.json, AppIcon.png}, AccentColor.colorset/Contents.json}`
- Crear: `scripts/generar_icono.py`, `scripts/verificar.py`
- Crear: `scripts/ci/instalar_herramientas.sh`, `scripts/ci/compilar_ipa.sh`, `scripts/ci/resumen_errores.sh`
- Crear: `.github/workflows/build.yml` (solo job `compilar`)

**Interfaces:**
- Produce: `enum InfoBuild { static var version, build, commit, sistema, modelo, resumen: String }`
  (`resumen` = `"Descargador 0.1.0 (build 12, commit abc1234) · iOS 17.6.1 · iPhone14,2"`).
- Produce: `scripts/ci/resumen_errores.sh <log>` (añade líneas `error:` al `$GITHUB_STEP_SUMMARY`).
- Produce: build setting `GIT_COMMIT` (por defecto `local`) → Info.plist `DescargadorCommit`.

- [ ] **Paso 1: `scripts/verificar.py`** — valida: `project.yml` y `.github/workflows/*.yml` parsean
  con PyYAML; cada `Contents.json` es JSON válido; `AppIcon.png` es 1024×1024 RGB sin alfa; cada
  `.swift` tiene `{}`/`()` balanceados fuera de cadenas y comentarios; cada ruta de `sources` en
  `project.yml` existe. Sale con código 1 y lista los fallos.
- [ ] **Paso 2: `python scripts/verificar.py`** → falla (aún no existen los archivos).
- [ ] **Paso 3: `scripts/generar_icono.py`** con Pillow: 1024×1024, degradado diagonal
  `#FF7A45`→`#E8364F`, flecha blanca hacia abajo sobre una bandeja, supermuestreo ×4, sin alfa.
  Ejecutarlo para crear `AppIcon.png`. AccentColor: claro `#E8442F`, oscuro `#FF6B4A`.
- [ ] **Paso 4: `project.yml`** — target `Descargador` (application) con `sources: [App/Sources, App/Resources]`,
  `info.path: App/Info.plist` y propiedades: `CFBundleDisplayName`, `CFBundleShortVersionString: $(MARKETING_VERSION)`,
  `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`, `CFBundleDevelopmentRegion: es`, `DescargadorCommit: $(GIT_COMMIT)`,
  `UILaunchScreen: {}`, orientaciones vertical + horizontales, `CFBundleURLTypes` con esquema `descargador`,
  `UIFileSharingEnabled: true`, `LSSupportsOpeningDocumentsInPlace: true`, `ITSAppUsesNonExemptEncryption: false`.
  Ajustes base: `MARKETING_VERSION 0.1.0`, `CURRENT_PROJECT_VERSION 1`, `GIT_COMMIT local`,
  `TARGETED_DEVICE_FAMILY 1`, `CODE_SIGN_STYLE Manual`, `CODE_SIGN_IDENTITY "-"`, `DEVELOPMENT_TEAM ""`,
  `ENABLE_USER_SCRIPT_SANDBOXING NO`, `ASSETCATALOG_COMPILER_APPICON_NAME AppIcon`. Esquema `Descargador`.
- [ ] **Paso 5: `InfoBuild.swift` + `DescargadorApp.swift` provisional** (`@main`, `WindowGroup` con un `Text`).
  `modelo` sale de `utsname.machine`; `sistema` de `UIDevice.current.systemVersion`.
- [ ] **Paso 6: scripts de CI.** `instalar_herramientas.sh`: descarga XcodeGen fijado a `$RUNNER_TEMP`
  y lo añade a `$GITHUB_PATH`; `brew install xcbeautify` (si falla, sigue sin él); selecciona
  `/Applications/Xcode_${XCODE_VERSION}.app` si existe; imprime `xcodebuild -version`.
  `compilar_ipa.sh`: `set -euo pipefail`; `xcodebuild -project Descargador.xcodeproj -scheme Descargador
  -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" GIT_COMMIT=<sha7>
  CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER build`, con `tee build/logs/xcodebuild.log` y
  `xcbeautify --renderer github-actions`; si falla llama a `resumen_errores.sh` y sale con 1; si va
  bien crea `build/Payload/Descargador.app` y `build/Descargador.ipa` (`zip -qry`) y escribe tamaño y
  SHA-256 en el Step Summary.
- [ ] **Paso 7: `build.yml`** — `on: push (branches main, tags v*), pull_request, workflow_dispatch`;
  `concurrency` por ref con cancelación; `permissions: contents: write`. Job `compilar`
  (`macos-26`, `timeout-minutes: 30`): checkout → herramientas → `xcodegen generate` → compilar →
  artifact `Descargador-ipa-${{ github.run_number }}` (`if-no-files-found: error`) → si falla,
  artifact `log-compilacion` con `build/logs/` → en tags `v*`, `gh release create` o, si ya existe,
  `gh release upload --clobber`.
- [ ] **Paso 8: `python scripts/verificar.py`** → `OK`.
- [ ] **Paso 9: commit** `git init -b main` (primera vez), `git add -A`, `git commit -m "Etapa 1: proyecto base y CI de compilación"`.
- [ ] **Verificar en CI:** job `compilar` verde; el artifact contiene `Descargador.ipa` con
  `Payload/Descargador.app/Info.plist`.

### Tarea 2: Núcleo (plataforma, calidad, enlaces, registro) con tests unitarios y job de simulador

**Archivos:**
- Crear: `App/Sources/Nucleo/Plataforma.swift`, `Calidad.swift`, `Enlaces.swift`, `Registro.swift`
- Crear: `Tests/Unitarias/PlataformaTests.swift`, `EnlacesTests.swift`, `RegistroTests.swift`
- Crear: `scripts/ci/probar_simulador.sh`
- Modificar: `project.yml` (target `DescargadorTests` `bundle.unit-test`, `GENERATE_INFOPLIST_FILE: YES`,
  dependiente de `Descargador`; añadirlo a `test` del esquema)
- Modificar: `.github/workflows/build.yml` (job `simulador`)

**Interfaces:**
- Produce:
  - `enum Plataforma: String, CaseIterable, Codable { youtube, instagram, tiktok, x, facebook, otra }`
    con `nombre: String` (`"YouTube"`, `"Instagram"`, `"TikTok"`, `"X"`, `"Facebook"`, `"Otra web"`),
    `simbolo: String` (SF Symbol) y `static func detectar(_ url: URL) -> Plataforma`.
  - `enum Calidad: String, CaseIterable, Codable, Identifiable { mejor, p1080 = "1080", p720 = "720", p480 = "480", p360 = "360", audio }`
    con `titulo` (`"Mejor"`, `"1080p"`, `"720p"`, `"480p"`, `"360p"`, `"Solo audio"`) y `alturaMaxima: Int?`.
  - `struct PeticionDescarga: Equatable { let url: URL; let calidad: Calidad? }`
  - `enum Enlaces { static func extraerPrimerEnlace(de texto: String) -> URL?; static func peticion(desde enlaceProfundo: URL) -> PeticionDescarga? }`
  - `enum NivelRegistro: String, Codable { depuracion, info, aviso, error }` con `etiqueta` (`DEBUG/INFO/AVISO/ERROR`).
  - `struct EntradaRegistro: Codable, Identifiable, Equatable { id: UUID; fecha: Date; nivel; categoria: String; mensaje: String; var lineaTexto: String }`
    (`"2026-11-09 10:00:00.123 [INFO] [app] mensaje"`).
  - `final class Registro: ObservableObject` — `static let compartido` (archivo `Caches/registro.jsonl`),
    `init(archivo: URL, maxEntradas: Int = 2000)`, `@Published private(set) var entradas: [EntradaRegistro]`,
    `registrar(_:_:categoria:)` seguro desde cualquier hilo, atajos `depurar/info/aviso/error(_:categoria:)`,
    `textoCompleto() -> String` (cabecera con `InfoBuild.resumen` + líneas), `limpiar()`, `esperarEscrituras()`.

- [ ] **Paso 1: tests de plataforma** — `PlataformaTests` con tabla URL → plataforma:
  `youtube`: `https://www.youtube.com/watch?v=a`, `https://youtu.be/a`, `https://m.youtube.com/shorts/a`,
  `https://music.youtube.com/watch?v=a`, `https://WWW.YOUTUBE.COM/watch?v=a`;
  `instagram`: `https://www.instagram.com/reel/abc/`, `https://instagr.am/p/abc`;
  `tiktok`: `https://www.tiktok.com/@u/video/1`, `https://vm.tiktok.com/ZMabc/`, `https://vt.tiktok.com/ZSabc/`;
  `x`: `https://x.com/u/status/1`, `https://twitter.com/u/status/1`, `https://mobile.twitter.com/u/status/1`;
  `facebook`: `https://www.facebook.com/watch/?v=1`, `https://fb.watch/abc/`, `https://m.facebook.com/story.php`, `https://fb.com/x`;
  `otra`: `https://vimeo.com/1`, `https://notyoutube.com/a`, `https://youtube.com.evil.net/a`.
- [ ] **Paso 2: tests de enlaces** (`EnlacesTests`):

```swift
// extraerPrimerEnlace
XCTAssertEqual(Enlaces.extraerPrimerEnlace(de: "Mira esto 😂 https://vm.tiktok.com/ZMabc123/ #fyp")?.absoluteString, "https://vm.tiktok.com/ZMabc123/")
XCTAssertNil(Enlaces.extraerPrimerEnlace(de: "hola mundo"))
XCTAssertNil(Enlaces.extraerPrimerEnlace(de: "mailto:a@b.com"))
XCTAssertNil(Enlaces.extraerPrimerEnlace(de: "ftp://x.com/a"))
XCTAssertEqual(Enlaces.extraerPrimerEnlace(de: "youtu.be/dQw4w9WgXcQ")?.host, "youtu.be")
XCTAssertEqual(Enlaces.extraerPrimerEnlace(de: "  \nhttps://x.com/a/status/1\n ")?.absoluteString, "https://x.com/a/status/1")
// peticion(desde:)
// codificada + calidad → url "https://www.youtube.com/watch?v=abc&t=10", calidad .p720
"descargador://download?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc%26t%3D10&calidad=720"
// test_peticionConUrlSinCodificar → url "https://www.youtube.com/watch?v=abc&t=10", calidad nil
"descargador://download?url=https://www.youtube.com/watch?v=abc&t=10"
// test_peticionConUrlSinCodificarYCalidad → misma url, calidad .audio
"descargador://download?url=https://www.youtube.com/watch?v=abc&t=10&calidad=audio"
// test_peticionSinCodificarConservaPorcentajes → url "https://a.com/b%20c"
"descargador://download?url=https://a.com/b%20c"
// calidad desconocida "4k" → calidad nil, url válida
// nil: "descargador://otra?url=https://a.com", "descargador://download?url=javascript:alert(1)",
//      "https://download?url=https://a.com", "descargador://download"
```

- [ ] **Paso 3: tests de registro** (`RegistroTests`, archivo temporal por test):
  `test_rotacionConservaLasUltimas`: `maxEntradas: 10`, registrar `m0…m24`, `esperarEscrituras()`,
  nuevo `Registro` sobre el mismo archivo → 10 entradas, primera `m15`, última `m24`; el archivo tiene
  ≤ 12 líneas. `test_lineaCorruptaSeIgnora`: archivo con línea válida + `{basura` + línea válida → 2
  entradas. `test_textoCompletoIncluyeCabeceraYLineas`: contiene `"Descargador"` y `"[ERROR] [prueba] fallo"`.
  `test_limpiarVaciaMemoriaYArchivo`: tras `limpiar()` y recargar → 0 entradas.
- [ ] **Paso 4: implementar `Plataforma`, `Calidad`.** Coincidencia de host: en minúsculas,
  `host == dominio || host.hasSuffix("." + dominio)`. Dominios: youtube `youtube.com, youtu.be,
  youtube-nocookie.com`; instagram `instagram.com, instagr.am`; tiktok `tiktok.com`; x `x.com,
  twitter.com`; facebook `facebook.com, fb.watch, fb.com`.
- [ ] **Paso 5: implementar `Enlaces`.** `extraerPrimerEnlace`: `NSDataDetector(.link)` sobre el
  texto recortado; primer resultado con esquema `http`/`https` y host no vacío. `peticion(desde:)`:

```text
1. esquema == "descargador" (sin distinguir mayúsculas) y host == "download"; si no → nil
2. q = percentEncodedQuery; localizar "url=" al inicio o tras "&"; valor = todo lo que sigue
3. si valor contiene "&calidad=" → partir en la ÚLTIMA aparición; calidad = Calidad(rawValue:) del resto (hasta "&")
4. si valor empieza por "http://" o "https://" (sin distinguir mayúsculas) → usar tal cual;
   si no → removingPercentEncoding
5. URL resultante debe tener esquema http/https y host; si no → nil
```

- [ ] **Paso 6: implementar `Registro`.** JSON Lines; cola serie para disco; publicación en el hilo
  principal (directa si ya está en él). Reescribe el archivo con las últimas `maxEntradas` cuando
  supera `maxEntradas + max(maxEntradas / 4, 2)` líneas. Al cargar: decodifica línea a línea,
  ignora las inválidas, se queda con las últimas `maxEntradas`. Fechas con `ISO8601DateFormatter`
  con milisegundos.
- [ ] **Paso 7: `probar_simulador.sh`** — elige el UDID de un iPhone disponible con runtime iOS 18
  (si no hay, cualquier iPhone) leyendo `xcrun simctl list devices available -j` con `python3`;
  lo arranca; `status_bar override --time 9:41`; `xcodebuild test ... -destination "id=$UDID"
  -resultBundlePath build/Resultados.xcresult` con `tee` + `xcbeautify --renderer github-actions`;
  si falla, `resumen_errores.sh`. Job `simulador` en `build.yml` (`macos-15`, `XCODE_VERSION: 26.3`):
  checkout → herramientas → `xcodegen generate` → probar → si falla, artifact `resultados-tests`
  con el `.xcresult`.
- [ ] **Paso 8: `python scripts/verificar.py`** → `OK`.
- [ ] **Paso 9: commit** `"Etapa 1: núcleo de enlaces, plataformas y registro con tests"`.
- [ ] **Verificar en CI:** job `simulador` verde con todos los tests unitarios en verde.

### Tarea 3: Interfaz (pestañas, Descargar, Historial, Ajustes, Registro)

**Archivos:**
- Crear: `App/Sources/App/EstadoApp.swift`
- Modificar: `App/Sources/App/DescargadorApp.swift` (raíz real)
- Crear: `App/Sources/Pantallas/Comun/Componentes.swift` (`VistaVacia`, `IconoPlataforma`; sin tokens propios: colores semánticos del sistema + acento del catálogo)
- Crear: `App/Sources/Pantallas/PestanasView.swift`
- Crear: `App/Sources/Pantallas/Descargar/{DescargarView, BannerPortapapeles, TarjetaEnlace}.swift`
- Crear: `App/Sources/Pantallas/Historial/HistorialView.swift`
- Crear: `App/Sources/Pantallas/Ajustes/AjustesView.swift`
- Crear: `App/Sources/Pantallas/Registro/RegistroView.swift`
- Crear: `Tests/Unitarias/EstadoAppTests.swift`

**Interfaces:**
- Consume: `Enlaces`, `Plataforma`, `Calidad`, `PeticionDescarga`, `Registro`, `InfoBuild` (Tareas 1-2).
- Produce:
  - `enum Pestana: String, CaseIterable, Hashable { descargar, historial, ajustes, registro }`
  - `enum Apariencia: String, CaseIterable { sistema, claro, oscuro }` con `esquema: ColorScheme?`
    (guardada en `@AppStorage("apariencia")`).
  - `@MainActor final class EstadoApp: ObservableObject` — `init(pestanaInicial: Pestana = .descargar, registro: Registro = .compartido)`;
    `@Published var pestana`, `textoEnlace: String`, `mensajeError: String?`, `calidadSolicitada: Calidad?`;
    `@Published private(set) var enlaceAnalizado: URL?`; `func analizar()`; `func usarTextoPegado(_ texto: String)`;
    `func abrir(enlaceProfundo url: URL)`.
  - Argumentos de lanzamiento (dominio de argumentos de `UserDefaults`): `-pestanaInicial <Pestana>`,
    `-apariencia <Apariencia>`, `-ultimoCambioPortapapeles <Int>`.
  - Identificadores de accesibilidad: `campoEnlace`, `botonPegar`, `botonAnalizar`,
    `bannerPortapapeles`, `botonUsarPortapapeles`, `botonDescartarPortapapeles`, `tarjetaEnlace`,
    `etiquetaPlataforma`, `mensajeError`, `listaRegistro`, `botonCopiarRegistro`.

- [ ] **Paso 1: tests de `EstadoApp`** (`@MainActor`, con `Registro` en archivo temporal):
  `test_abrirEnlaceProfundoRellenaYAnaliza` (`descargador://download?url=https://youtu.be/abc&calidad=720`
  → `pestana == .descargar`, `textoEnlace == "https://youtu.be/abc"`, `enlaceAnalizado?.host == "youtu.be"`,
  `calidadSolicitada == .p720`); `test_analizarTextoInvalidoMuestraError` (`"hola"` → `enlaceAnalizado == nil`,
  `mensajeError == "Eso no parece un enlace. Copia el enlace del video y pégalo aquí."`);
  `test_usarTextoPegadoExtraeEnlace` (`"mira https://x.com/u/status/1 jaja"` → `textoEnlace == "https://x.com/u/status/1"`);
  `test_enlaceProfundoInvalidoNoCambiaNada` (`descargador://otra` → `textoEnlace == ""`, registro con un `aviso`).
- [ ] **Paso 2: diseño.** Cargar la skill `impeccable` para criterios de pantallas iOS nativas;
  fijar tokens en `Estilo.swift` (espaciados, radios, tipografía con estilos dinámicos, color de
  acento del asset catalog). Solo colores semánticos del sistema para fondos y textos.
- [ ] **Paso 3: implementar `EstadoApp`** — registra cada acción en `Registro` (categoría `ui`).
- [ ] **Paso 4: `DescargadorApp` + `PestanasView`** — `TabView` con las 4 pestañas (SF Symbols),
  `.onOpenURL { estado.abrir(enlaceProfundo:) }`, `.preferredColorScheme(apariencia.esquema)`,
  registra al arrancar `"Inicio · \(InfoBuild.resumen)"`.
- [ ] **Paso 5: `DescargarView`** — título, `TextField` (teclado URL, sin autocorrección ni
  mayúsculas, botón limpiar), `PasteButton(payloadType: String.self)` → `usarTextoPegado`, botón
  "Analizar" (deshabilitado si el campo está vacío), `mensajeError` en rojo, `TarjetaEnlace`
  (símbolo + nombre de plataforma, host, nota "El análisis completo llega en la Etapa 2").
  `BannerPortapapeles`: al aparecer y al volver a `.active`, `UIPasteboard.general.detectPatterns(for: [.probableWebURL])`;
  se muestra solo si `changeCount != @AppStorage("ultimoCambioPortapapeles")`; "Usar" es un
  `PasteButton`; "Usar" y "Descartar" guardan el `changeCount`.
- [ ] **Paso 6: `HistorialView`** — estado vacío propio (no `ContentUnavailableView`, que es iOS 17).
- [ ] **Paso 7: `AjustesView`** — `Form`: Apariencia (`Picker`), Acerca de (versión, build, commit,
  iOS, modelo), Motor de descarga ("Pendiente — Etapa 2").
- [ ] **Paso 8: `RegistroView`** — `List` monoespaciada con color por nivel, autodesplazamiento al
  final, barra con Copiar (`UIPasteboard.general.string = textoCompleto()` + confirmación
  "Copiado"), `ShareLink` del texto y Borrar con `confirmationDialog`.
- [ ] **Paso 9: `python scripts/verificar.py`** → `OK`.
- [ ] **Paso 10: commit** `"Etapa 1: interfaz con pestañas, pegar enlace y registro"`.
- [ ] **Verificar en CI:** ambos jobs verdes.

### Tarea 4: UI tests con capturas en claro y oscuro

**Archivos:**
- Crear: `Tests/UI/RecorridoUITests.swift`
- Crear: `scripts/ci/exportar_capturas.py`
- Modificar: `project.yml` (target `DescargadorUITests` `bundle.ui-testing`, `TEST_TARGET_NAME: Descargador`; en el esquema)
- Modificar: `scripts/ci/probar_simulador.sh`, `.github/workflows/build.yml` (artifact `capturas-simulador`, `if: always()`)

**Interfaces:**
- Consume: argumentos de lanzamiento e identificadores de accesibilidad de la Tarea 3.
- Produce: helper `capturar(_ nombre: String)` (adjunto `.keepAlways`).

- [ ] **Paso 1: tests.** `test_recorridoConCapturas`: para `claro` y `oscuro`, lanzar con
  `-apariencia <x> -ultimoCambioPortapapeles <changeCount actual>`; capturas `01-descargar-<x>`,
  `02-historial-<x>`, `03-ajustes-<x>`, `04-registro-<x>`; escribir
  `https://www.youtube.com/watch?v=dQw4w9WgXcQ` en `campoEnlace`, pulsar `botonAnalizar`,
  esperar `etiquetaPlataforma` con label `"YouTube"`, captura `05-analizado-<x>`.
  `test_enlaceInvalidoMuestraError`: `"hola"` → existe `mensajeError`.
  `test_bannerPortapapeles`: `UIPasteboard.general.string = "https://vm.tiktok.com/ZMabc/"`, lanzar con
  `-ultimoCambioPortapapeles -1` → `bannerPortapapeles` en ≤ 5 s, captura `06-banner-portapapeles`.
  `test_bannerPortapapelesNoSeRepite`: tras pulsar `botonDescartarPortapapeles`, terminar y relanzar
  la app sin argumento → el banner no aparece en 3 s.
  `test_esquemaDeUrl` (iOS 16.4+): `XCUIDevice.shared.system.open(URL(string: "descargador://download?url=https%3A%2F%2Fx.com%2Fu%2Fstatus%2F1")!)`
  → `etiquetaPlataforma` = `"X"`, captura `07-enlace-profundo`.
- [ ] **Paso 2: `exportar_capturas.py <xcresult> <destino>`** — ejecuta
  `xcrun xcresulttool export attachments`, renombra con `manifest.json` (nombre del adjunto) y deja
  solo los `.png`.
- [ ] **Paso 3: CI** — `probar_simulador.sh` llama al exportador también si los tests fallan; el
  job sube `capturas-simulador` con `if: always()`.
- [ ] **Paso 4: `python scripts/verificar.py`** → `OK`.
- [ ] **Paso 5: commit** `"Etapa 1: UI tests con capturas del simulador"`.
- [ ] **Verificar en CI:** artifact `capturas-simulador` con 12 PNG (5 × 2 apariencias + `06` + `07`) y ningún test en rojo.

### Tarea 5: README en español

**Archivos:** Crear `README.md`.

- [ ] **Paso 1: comprobar fuentes vigentes** — documentación de SideStore (instalación desde
  Windows en iOS 17.6.1, VPN/pairing actual) y de AltStore/AltServer para Windows.
- [ ] **Paso 2: escribir** las secciones: (1) subir a GitHub público desde VS Code ("Publicar
  rama" → repositorio público; el repo ya tiene `git init` y está dentro de otro repo en
  `D:\Programacion`, cómo distinguirlos); (2) descargar el `.ipa` (artifact y Releases con tag
  `v0.1.0`, también desde Safari del iPhone); (3) SideStore paso a paso (recomendado) y AltStore
  desde Windows, renovación cada 7 días y límites de la cuenta gratuita; (4) Atajos: atajo con
  "Codificar URL" + "Abrir URL" `descargador://download?url=…` (la acción nativa llega en la
  Etapa 5); (5) solución de problemas (dónde está el error en Actions, log artifact, Registro de la
  app, errores típicos de SideStore); (6) qué probar en la Etapa 1 y qué enviarme si falla.
- [ ] **Paso 3: commit** `"Etapa 1: README en español"`.
