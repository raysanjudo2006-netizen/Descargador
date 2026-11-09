# Descargador

App de iOS para uso personal que descarga videos de YouTube, Instagram, TikTok, X y Facebook
directamente en el iPhone, sin servidor. Se compila gratis en GitHub Actions y se instala con
SideStore (o AltStore) usando un Apple ID gratuito.

> **Estado: Etapa 1 de 5.** La app ya se instala, detecta enlaces y plataformas, abre enlaces
> `descargador://` y tiene Registro. La descarga real llega en las Etapas 2 y 3.

| Etapa | Contenido | Estado |
|---|---|---|
| 1 | Esqueleto SwiftUI + compilación en GitHub Actions + pruebas en simulador | ✅ |
| 2 | Python + yt-dlp dentro de la app | ⏳ |
| 3 | Descarga con progreso real, unión de audio y video, guardado en Fotos | ⏳ |
| 4 | YouTube (motor JavaScript) | ⏳ |
| 5 | Share Extension, Atajos, historial, ajustes completos | ⏳ |

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

### SideStore (recomendado: renueva desde el propio iPhone)

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

## 4. Atajos (app Atajos de iOS)

La acción nativa "Descargar video" llega en la Etapa 5. Mientras tanto, la app ya responde al
enlace `descargador://download?url=…`, y con eso basta para un atajo que aparece en el botón
Compartir:

1. Abre **Atajos** → **+** → nombre: *Descargar video*.
2. Toca el icono de información (ⓘ) → activa **Mostrar en la hoja para compartir** y deja que
   reciba **URL** y **Texto**.
3. Añade estas acciones en orden:
   1. **Codificar URL** (*URL Encode*) → entrada: *Entrada del atajo*.
   2. **Texto** → escribe `descargador://download?url=` y, justo detrás, inserta la variable
      *Texto codificado*. Opcional: añade `&calidad=720` al final (valores: `mejor`, `1080`,
      `720`, `480`, `360`, `audio`).
   3. **Abrir URLs** → con el *Texto* anterior.
4. Pruébalo: en YouTube o TikTok pulsa **Compartir › Descargar video**.

Prueba rápida sin atajo: escribe en la barra de Safari
`descargador://download?url=https://youtu.be/dQw4w9WgXcQ&calidad=720`.

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

## 6. Etapa 1: qué probar y qué enviarme

1. **Actions:** los dos trabajos con ✅. En **capturas-simulador** debe haber 12 imágenes
   (pantallas en claro y oscuro, aviso del portapapeles y enlace `descargador://`).
2. **Instalar:** el `.ipa` se instala con SideStore y la app abre con el icono naranja.
3. **Pegar:** copia un enlace de YouTube en otra app y vuelve a Descargador. Debe aparecer
   "Tienes un enlace copiado"; toca el icono de pegar y debe salir la tarjeta "YouTube".
4. **Error:** escribe `hola` y pulsa **Analizar enlace**. Debe salir un aviso en rojo.
5. **Esquema:** en Safari, abre
   `descargador://download?url=https%3A%2F%2Fx.com%2Fu%2Fstatus%2F1&calidad=720`. Se abre la app
   con "X" y "Calidad pedida: 720p".
6. **Ajustes:** cambia el tema a Oscuro y a Claro.

**Si algo falla, envíame:**

- El bloque **Summary** de Actions si falló la compilación o los tests.
- El texto de **Registro › Copiar** si falló algo dentro de la app.
- Una captura de pantalla del iPhone si algo se ve mal.

## Estructura del proyecto

```text
App/Sources/App/         Arranque, estado global, datos de la compilación
App/Sources/Nucleo/      Lógica sin interfaz: enlaces, plataformas, calidades, registro
App/Sources/Pantallas/   Vistas SwiftUI (Descargar, Historial, Ajustes, Registro)
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
