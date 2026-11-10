# Descargador

App de iOS para uso personal que descarga videos de YouTube, Instagram, TikTok, X y Facebook
directamente en el iPhone, sin servidor. Se compila gratis en GitHub Actions y se instala con
SideStore (o AltStore) usando un Apple ID gratuito.

> **Estado: las 5 etapas están hechas (pendientes de probar en el iPhone).** La app analiza el enlace con yt-dlp (Python dentro de la app),
> descarga con progreso real, une audio y video sin ffmpeg y guarda el video en Fotos o el audio
> en Archivos. YouTube funciona completo: los desafíos JavaScript se resuelven con
> JavaScriptCore, el motor de iOS. yt-dlp se actualiza desde Ajustes sin reinstalar. Además:
> historial, Descargador en el botón Compartir, acción "Descargar video" en Atajos y cookies.

| Etapa | Contenido | Estado |
|---|---|---|
| 1 | Esqueleto SwiftUI + compilación en GitHub Actions + pruebas en simulador | ✅ |
| 2 | Python + yt-dlp dentro de la app (analizar enlaces) | ✅ |
| 3 | Descarga con progreso real, unión de audio y video, Fotos/Archivos, actualizar yt-dlp | 🧪 en pruebas |
| 4 | YouTube (desafíos JavaScript con JavaScriptCore) | 🧪 en pruebas |
| 5 | Compartir (Share Extension), acción de Atajos, historial, cookies, calidad predeterminada | 🧪 en pruebas |

---

## 1. Subir el proyecto a GitHub (público) desde Windows y VS Code

El repositorio tiene que ser **público**: así los Mac de GitHub Actions son gratis.

1. Crea una cuenta en <https://github.com> si no tienes.
2. Abre **la carpeta `DescargarVideos`** en VS Code (*Archivo › Abrir carpeta…*).
   La carpeta ya es un repositorio git con su historial.
3. Ve a la vista **Control de código fuente** (icono de ramas, `Ctrl+Shift+G`).
   - Si ves dos repositorios (`DescargarVideos` y `Programacion`), usa **DescargarVideos**.
     `D:\Programacion` es otro repositorio tuyo y este proyecto vive dentro, pero es independiente.
     No hagas `git add` de esta carpeta desde el repositorio de `D:\Programacion`.
4. Pulsa **Publicar rama** (*Publish Branch*) y, cuando lo pregunte:
   - inicia sesión en GitHub,
   - elige **Publicar en un repositorio público de GitHub**,
   - ponle de nombre `Descargador`.
5. Abre el repositorio en github.com y entra en la pestaña **Actions**. La primera ejecución de
   **Compilar** empieza sola. Tarda unos 10-15 minutos.

<details>
<summary>Alternativa por terminal</summary>

Crea en github.com un repositorio **público** vacío llamado `Descargador` (sin README) y, en la
terminal de VS Code (`Ctrl+ñ`), dentro de la carpeta del proyecto:

```powershell
git remote add origin https://github.com/TU_USUARIO/Descargador.git
git push -u origin main
```
</details>

A partir de ahí, cada cambio se publica con **Sincronizar cambios** en VS Code (o `git push`) y
GitHub vuelve a compilar.

## 2. Descargar el `.ipa`

El workflow tiene dos trabajos:

- **Compilar .ipa (iPhone):** genera `Descargador.ipa` sin firmar.
- **Probar en simulador (iOS 18):** ejecuta los tests en un iPhone simulado y saca capturas de
  cada pantalla, en claro y oscuro.

### Opción A — Releases (la más cómoda para el iPhone)

Cada vez que publicas una etiqueta `v…`, el workflow crea una *Release* con el `.ipa` adjunto. Se
descarga sin iniciar sesión, directamente desde Safari en el iPhone.

1. En la terminal de VS Code:

   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. Espera a que termine la ejecución en **Actions**.
3. En el iPhone, abre en Safari `https://github.com/TU_USUARIO/Descargador/releases`, toca
   `Descargador.ipa` y descárgalo. Queda en **Archivos › Descargas**.

Para la siguiente versión usa otro número (`v0.1.1`, `v0.2.0`…).

### Opción B — Artifacts (cualquier push)

1. **Actions** → la última ejecución de **Compilar** (con ✅).
2. Abajo del todo, en **Artifacts**, descarga `Descargador-ipa-N` (es un `.zip`).
3. Descomprímelo: dentro está `Descargador.ipa`. Para llevarlo al iPhone sin Mac, lo más fácil
   es la Opción A: GitHub funciona desde Cuba, mientras que iCloud u otros servicios pueden no
   cargar.

En la misma página está **capturas-simulador**: imágenes de la app funcionando en un iPhone
simulado, para ver cómo queda cada cambio antes de instalarlo.

## 3. Instalar en el iPhone

Límites de un Apple ID gratuito (los pone Apple, no esta app):

- Las apps caducan a los **7 días** y hay que renovarlas (no se pierden los datos).
- Máximo **3 apps** instaladas así a la vez, **contando SideStore/AltStore**.
- Máximo **10 App IDs por semana**. La Share Extension de la Etapa 5 gastará uno más.

### Con iloader desde el PC (lo que funciona ahora)

Desde el 12 de octubre de 2026, Apple rechaza el inicio de sesión de SideStore en el iPhone
(error **-80045**) en todas las herramientas gratuitas. iloader, en cambio, sí inicia sesión desde
el PC, así que de momento Descargador se instala y se renueva con él:

1. Descarga `Descargador.ipa` en el PC (apartado 2).
2. Conecta el iPhone por cable y desbloquéalo.
3. En iloader pulsa **Import IPA**, elige `Descargador.ipa` y espera a que termine.
4. La primera vez: **Ajustes › General › VPN y gestión de dispositivos** → tu Apple ID →
   **Confiar**, y **Ajustes › Privacidad y seguridad › Modo de desarrollador** → activado.

**Cada 7 días** (o al instalar una versión nueva) repite los pasos 2 y 3. No se pierden los datos.

Si SideStore publica un arreglo del -80045, podrás volver a renovar desde el iPhone. Hay un
arreglo no oficial con la versión *Nightly* y el servidor de anisette "SideStore (New)"; ver
[SideStore #1709](https://github.com/SideStore/SideStore/issues/1709).

### SideStore (renueva desde el propio iPhone cuando el inicio de sesión funcione)

**Una sola vez, en el iPhone:**

1. El iPhone necesita código de desbloqueo y estar en Wi-Fi.
2. Instala **LocalDevVPN** desde la App Store, ábrela y pulsa **Conectar**. Acepta "Permitir
   configuraciones VPN". SideStore la necesita encendida cada vez que instala o renueva.

**Una sola vez, en el PC con Windows:**

3. Instala **iTunes** (sirve el de Microsoft Store o el de apple.com): aporta el controlador USB.
4. Descarga **iloader** para Windows (`iloader-windows-x64.msi`) desde
   <https://github.com/nab138/iloader/releases/latest> e instálalo.
5. Conecta el iPhone por cable, desbloquéalo y toca **Confiar** si lo pregunta.
6. Abre iloader, inicia sesión con tu Apple ID (distingue mayúsculas), elige tu iPhone y pulsa
   **Install SideStore (Stable)**.

**En el iPhone, para terminar:**

7. **Ajustes › General › VPN y gestión de dispositivos** → en "App de desarrollador" toca tu
   Apple ID → **Confiar**.
8. **Ajustes › Privacidad y seguridad › Modo de desarrollador** → actívalo. El iPhone se
   reinicia; al volver confirma **Activar**.
9. Abre LocalDevVPN → **Conectar**. Abre **SideStore** e inicia sesión con el mismo Apple ID.
10. En **Mis apps**, toca el contador **7 DÍAS** junto a SideStore para terminar la
    configuración. Si pregunta por crear o revocar un certificado, acepta.

**Instalar Descargador:**

11. Descarga `Descargador.ipa` en el iPhone (apartado 2, opción A).
12. Con LocalDevVPN conectada: SideStore → **Mis apps** → **+** → elige `Descargador.ipa` en
    Archivos › Descargas. Espera a que termine.
13. Abre **Descargador**.

**Renovar cada 7 días (o antes):** en Wi-Fi, conecta LocalDevVPN, abre SideStore → **Mis apps** →
**Actualizar todo**. Si llegara a caducar, la app no abre hasta que la renuevas, pero tus datos
siguen ahí.

**Actualizar a una versión nueva:** instala el `.ipa` nuevo igual que en el paso 12; sustituye al
anterior y mantiene los datos.

### AltStore desde Windows (alternativa)

AltStore necesita el PC encendido con AltServer en la misma Wi-Fi para renovar.

1. Instala **iTunes** e **iCloud** descargados de apple.com, **no** los de Microsoft Store:
   iTunes <https://www.apple.com/itunes/download/win64> · iCloud
   <https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe>
2. Descarga **AltServer para Windows** (<https://cdn.altstore.io/file/altstore/altinstaller.zip>),
   descomprímelo y ejecuta `Setup.exe`.
3. Busca "AltServer" en Inicio → **Ejecutar como administrador**. Aparece un icono junto al reloj.
4. Conecta el iPhone, desbloquéalo y confía en el PC. Abre iTunes, inicia sesión y activa
   **Sincronizar con este iPhone por Wi-Fi**.
5. Icono de AltServer → **Install AltStore** → tu iPhone → tu Apple ID.
6. En el iPhone: **Ajustes › General › VPN y gestión de dispositivos** → **Confiar**. Luego
   **Ajustes › Privacidad y seguridad › Modo de desarrollador** → activar.
7. Instalar Descargador: en AltStore → **Mis apps** → **+** → `Descargador.ipa` (AltServer
   abierto y en la misma Wi-Fi). O desde el PC: `Mayús` + clic en el icono de AltServer →
   **Sideload .ipa…**.
8. Renovar: con AltServer abierto en el PC y la misma Wi-Fi, AltStore → **Mis apps** →
   **Actualizar todo**.

## 4. Compartir y Atajos

### Descargador en el botón Compartir

En YouTube, TikTok, Instagram, X o Safari pulsa **Compartir** y elige **Descargador** en la fila
de apps. Si no aparece, desliza esa fila hasta el final → **Más** → activa Descargador (y
arrástralo arriba). La app se abre con el enlace, lo analiza y:

- si en **Ajustes › Calidad para Compartir y Atajos** elegiste una calidad, descarga sola;
- si está en "Preguntar", te deja elegir la calidad.

En Instagram y TikTok a veces hay que tocar primero **Compartir en…** o **Más** para que salga la
hoja de Compartir de iOS.

> Con la cuenta gratuita, la extensión gasta un App ID más al instalar con iloader (tienes 10
> por semana). Si iloader da error de límite de App IDs, espera unos días o avísame.

### Acción "Descargar video" en Atajos

1. **Atajos** → **+** → busca la acción **Descargar video** (de Descargador).
2. **Enlace**: toca y elige *Entrada del atajo*. **Calidad**: la que quieras.
3. Toca ⓘ → activa **Mostrar en la hoja para compartir** (recibe URL y Texto).
4. Ya aparece en Compartir como *Descargar video*. También con Siri: "Descargar video con
   Descargador".

El enlace `descargador://download?url=…&calidad=720` sigue funcionando (desde Safari o con
"Abrir URLs" en un atajo). La app acepta también el texto compartido entero de TikTok o
Instagram y busca el enlace dentro.

## Historial

La pestaña **Historial** guarda cada descarga con su miniatura, título, plataforma, tamaño y
fecha. Toca para reproducir; desliza a la izquierda para borrar; mantén pulsado para compartir.
Borrar quita la copia de la app, no la de Fotos.

## Cookies (opcional)

Solo hacen falta si un video pide tu sesión: privado, con restricción de edad, o cuando YouTube
dice "confirma que no eres un robot".

1. En el navegador del PC, con tu cuenta abierta en la web (por ejemplo youtube.com), exporta las
   cookies con una extensión como **Get cookies.txt LOCALLY** (formato Netscape, `cookies.txt`).
2. Pásalo al iPhone sin iCloud: conecta el iPhone por cable, abre **iTunes** → tu iPhone →
   **Compartir archivos** → **Descargador** → arrastra `cookies.txt` a la lista.
3. En la app: **Ajustes › Cookies › Importar cookies.txt** → En mi iPhone › Descargador.
4. Para quitarlas: **Ajustes › Cookies › Borrar cookies**.

Las cookies son como tu contraseña: se guardan solo dentro de la app, nunca en el Registro, y no
debes compartirlas. Borra el `cookies.txt` del PC cuando termines.

## 5. Solución de problemas

**La compilación falla (❌ en Actions)**

- Abre la ejecución y mira **Summary**: el bloque "❌ Falló…" muestra los primeros errores.
  **Cópialos y pégamelos.**
- Los errores también salen marcados en rojo en las líneas del paso que falló.
- Al final de la página está el log completo: **log-compilacion** si falló la compilación del
  `.ipa`, **resultados-tests** si fallaron los tests del simulador.
- Si los tests fallan, mira también **capturas-simulador**: suele verse qué pantalla falló.

**Actions no se ejecuta**

- El repositorio debe ser público.
- En **Settings › Actions › General**, comprueba que esté permitido ejecutar acciones.
- Puedes lanzarlo a mano en **Actions › Compilar › Run workflow**.

**SideStore**

| Mensaje o síntoma | Qué hacer |
|---|---|
| Falla al instalar o renovar, o habla de VPN o conexión | Abre LocalDevVPN, pulsa Conectar y vuelve a intentarlo en Wi-Fi. |
| Límite de apps o de App IDs | Borra una app instalada con SideStore, o espera a que pasen 7 días desde que se crearon los IDs. |
| No acepta tu Apple ID | Revisa mayúsculas y minúsculas; actualiza SideStore con iloader. |
| "No se puede verificar la app" o no abre | Ha caducado: renuévala en SideStore → Actualizar todo. |

**Desde Cuba**

GitHub (repositorio público, Actions y Releases) está disponible para desarrolladores en Cuba
según su política de exportación. Algunos servicios de Apple o de Microsoft pueden no cargar
desde una conexión cubana: la descarga de iTunes, la Microsoft Store, la App Store (para
LocalDevVPN) o el inicio de sesión del Apple ID en iloader, SideStore o AltServer. Si un paso
falla así, el problema es la conexión con ese servicio, no esta app. Anota en qué paso ocurre y
dímelo.

**La app se cierra o algo va mal**

1. Vuelve a abrir Descargador → pestaña **Registro** (guarda lo anterior a un cierre).
2. Toca **Copiar** (arriba a la derecha) y pégamelo en el chat.
3. En **Ajustes › Acerca de** está la versión, el build y el commit; **Copiar información** lo
   copia todo junto.

## 6. Qué probar en cada etapa y qué enviarme

### Etapa 5: Compartir, Atajos, historial y cookies

1. **Compartir:** en YouTube o TikTok, **Compartir › Descargador**. Se abre la app con el enlace.
2. **Calidad predeterminada:** Ajustes › *Calidad para Compartir y Atajos* → 720p. Repite el
   paso 1: ahora debe descargar solo.
3. **Atajos:** crea el atajo con la acción **Descargar video** (apartado 4) y úsalo desde
   Compartir.
4. **Historial:** las descargas anteriores aparecen con miniatura; prueba reproducir, compartir
   y borrar.
5. **Cookies (si hace falta):** importa un `cookies.txt` y analiza un video que antes pedía
   iniciar sesión.

### Etapa 4: YouTube

1. Analiza un enlace de YouTube (`youtube.com/watch?v=…`, `youtu.be/…` o un Short). Deben salir
   las calidades hasta 1080p (en YouTube, "Mejor" es como mucho 1080p: el 4K solo existe en
   formatos que Fotos no acepta sin recodificar).
2. En **Registro** debe aparecer "Desafío de YouTube resuelto con JavaScriptCore en X s". La
   primera vez tarda unos segundos: iOS no deja usar el modo rápido (JIT) a apps instaladas así.
3. Descarga en 720p y comprueba en Fotos que tiene sonido (YouTube manda video y audio separados:
   verás "Uniendo audio y video").
4. Si YouTube responde "confirma que no eres un robot", la solución son tus cookies (Etapa 5).

### Etapa 3: descargar, unir y guardar

1. **Instalar:** etiqueta `v0.3.0` (apartado 2) e instálalo con iloader.
2. **Descargar video:** analiza un enlace de TikTok, X o Instagram y **toca una calidad**. Debe
   verse la barra con %, MB descargados de MB totales, velocidad y tiempo restante. Si video y
   audio vienen separados, después sale **"Uniendo audio y video"**.
3. **Resultado:** "Guardado en Fotos y en Archivos". La primera vez iOS pide permiso para añadir
   a Fotos. Comprueba en **Fotos** que el video tiene sonido. Prueba **Compartir** y **Abrir**.
4. **Solo audio:** toca "Solo audio". El `.m4a` queda en **Archivos › En mi iPhone ›
   Descargador › Descargas**.
5. **Cancelar:** empieza una descarga grande y pulsa **Cancelar descarga**.
6. **Segundo plano:** empieza una descarga larga y sal de la app.
   - Sin "Mantener activo": a los ~30 s llega el aviso "Descarga en pausa"; al volver, continúa.
   - Con **Ajustes › Mantener activo en segundo plano**: sigue descargando fuera de la app.
7. **Actualizar yt-dlp:** Ajustes › **Buscar actualización de yt-dlp**. Si hay una nueva,
   **Instalar**, cierra la app y ábrela: debe decir "(actualizado)". "Volver al yt-dlp incluido"
   lo deshace.
8. **Atajo con calidad:** en Safari abre
   `descargador://download?url=https%3A%2F%2Fx.com%2FNASA%2Fstatus%2F1&calidad=360` (cambia la
   URL por un tuit con video): debe analizar y descargar solo.

### Etapa 2: Python + yt-dlp ✅

Compilación y pruebas en el simulador en verde (Python 3.14.10, yt-dlp 2026.10.26).

<details>
<summary>Pruebas de la Etapa 2</summary>


1. **Actions:** los tres trabajos con ✅ (*Compilar*, *Probar en simulador* y *Tests de Python*).
   En **capturas-simulador**, la de Ajustes debe mostrar yt-dlp `2026.10.26`.
2. **Instalar:** crea la etiqueta `v0.2.0` (apartado 2) e instala el `.ipa` con iloader.
   Ahora pesa más (unos 15-25 MB) porque lleva Python dentro.
3. **Ajustes › Motor de descarga:** Python `3.14.10`, yt-dlp `2026.10.26`, yt-dlp-ejs `0.8.0`.
   La primera vez tarda uno o dos segundos.
4. **Analizar:** pega enlaces de **TikTok**, **X** e **Instagram** y pulsa **Analizar enlace**.
   Deben salir miniatura, título, autor, duración y la lista de calidades con su tamaño.
5. **YouTube:** puede funcionar a medias (sin algunas calidades) o dar un error: el motor
   JavaScript que necesita llega en la Etapa 4. Pruébalo igualmente y mándame el resultado.
6. **Error claro:** activa el modo avión y analiza un enlace: debe decir que no hay conexión.

</details>

### Etapa 1: esqueleto ✅

Pegar y detectar enlaces, aviso del portapapeles, enlace `descargador://`, tema claro/oscuro y
Registro. Probado en el iPhone el 9 de noviembre de 2026.

**Si algo falla, envíame:**

- El bloque **Summary** de Actions si falló la compilación o los tests.
- El texto de **Registro › Copiar** si falló algo dentro de la app.
- Una captura de pantalla del iPhone si algo se ve mal.

## Estructura del proyecto

```text
App/Sources/App/         Arranque, estado global, acción de Atajos, buzón de enlaces
App/Sources/Nucleo/      Lógica sin interfaz: enlaces, calidades, registro, cookies, formatos
App/Sources/Python/      Puente C con Python, MotorPython, JavaScriptCore, actualizar yt-dlp
App/Sources/Descargas/   Gestor de descargas y segundo plano
App/Sources/Medios/      Unir/extraer con AVFoundation y guardar en Fotos/Archivos
App/Sources/Historial/   Historial de descargas
App/Sources/Pantallas/   Vistas SwiftUI (Descargar, Historial, Ajustes, Registro)
App/python/app/          Código Python propio (puente con yt-dlp, selección de formatos)
ShareExtension/          Descargador en el botón Compartir
App/Resources/           Icono y color de acento
Tests/Unitarias/         Tests de la lógica
Tests/UI/                Recorrido de la app con capturas
scripts/ci/              Scripts que usa GitHub Actions
scripts/verificar.py     Comprobaciones que se pueden ejecutar en Windows
project.yml              Definición del proyecto (XcodeGen genera el .xcodeproj en CI)
docs/superpowers/        Diseño y planes de cada etapa
```

Antes de hacer push puedes ejecutar `python scripts/verificar.py`. Revisa YAML, JSON, el icono y
que las llaves de los `.swift` estén cerradas. No sustituye al compilador, pero evita gastar una
ejecución de Actions en un error tonto.
