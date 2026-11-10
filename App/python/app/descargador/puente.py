"""Puente entre Swift y yt-dlp.

Swift (a través de PuentePython.c) llama a estas funciones con tres argumentos:
    funcion(peticion_json: str, direccion_callback: int, contexto: int) -> str (JSON)

- La respuesta siempre es JSON: {"ok": true, "datos": …} o {"ok": false, "error": {…}}.
- Los eventos (registro y, más adelante, progreso) se envían a Swift por un callback C
  `int callback(const char *evento_json, void *contexto)`; si devuelve 1, Swift pide cancelar.
"""
from __future__ import annotations

import copy
import ctypes
import functools
import json
import os
import platform
import re
import time
import traceback
import zipfile

from . import errores, seleccion

TIPO_CALLBACK = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p)

# Últimos análisis {url: (momento, info)}: descargar los reutiliza para no volver a extraer
# (en YouTube eso evita resolver otra vez el desafío JavaScript). Los enlaces de los
# formatos duran horas; se reutilizan como mucho 30 minutos.
_ANALISIS_RECIENTES: dict = {}
_VIGENCIA_ANALISIS = 30 * 60
_MAXIMO_ANALISIS = 5


def _guardar_analisis(url: str, info: dict):
    _ANALISIS_RECIENTES[url] = (time.monotonic(), info)
    while len(_ANALISIS_RECIENTES) > _MAXIMO_ANALISIS:
        mas_viejo = min(_ANALISIS_RECIENTES, key=lambda clave: _ANALISIS_RECIENTES[clave][0])
        del _ANALISIS_RECIENTES[mas_viejo]


def _analisis_reciente(url: str):
    guardado = _ANALISIS_RECIENTES.get(url)
    if guardado and time.monotonic() - guardado[0] < _VIGENCIA_ANALISIS:
        return copy.deepcopy(guardado[1])
    return None


class Emisor:
    """Envía eventos JSON a Swift por el callback C."""

    def __init__(self, direccion: int, contexto: int):
        self._callback = TIPO_CALLBACK(direccion) if direccion else None
        self._contexto = contexto or None

    def emitir(self, evento: dict) -> bool:
        """Envía un evento. Devuelve True si Swift pide cancelar."""
        if self._callback is None:
            return False
        try:
            datos = json.dumps(evento, ensure_ascii=False).encode("utf-8")
            return self._callback(datos, self._contexto) == 1
        except Exception:  # un fallo al avisar no debe romper la descarga
            return False

    def log(self, nivel: str, mensaje) -> bool:
        return self.emitir({"tipo": "log", "nivel": nivel, "mensaje": str(mensaje)})


class _Cancelacion:
    """Petición de cancelar compartida por el logger y los progress hooks de una descarga.

    Una vez activada, cada llamada siguiente vuelve a lanzar DownloadCancelled: así se paran
    también los hilos que descargan fragmentos (HLS/DASH) en paralelo.
    """

    def __init__(self):
        self.activa = False

    def comprobar(self):
        if self.activa:
            from yt_dlp.utils import DownloadCancelled
            raise DownloadCancelled("Cancelado por el usuario")


class _RegistroYtDlp:
    """Logger para yt-dlp: reenvía todo al Registro de la app y guarda los avisos.

    Si se le da una cancelación, cada mensaje sirve también para enterarse de que Swift
    pidió cancelar (por ejemplo, durante el análisis, antes de que haya progreso).
    """

    def __init__(self, emisor: Emisor, cancelacion: "_Cancelacion | None" = None):
        self.emisor = emisor
        self.cancelacion = cancelacion
        self.avisos: list[str] = []

    def _enviar(self, nivel: str, mensaje):
        pide_cancelar = self.emisor.log(nivel, mensaje)
        if self.cancelacion is not None:
            if pide_cancelar:
                self.cancelacion.activa = True
            self.cancelacion.comprobar()

    def debug(self, mensaje):
        # Con un logger, yt-dlp manda aquí también los mensajes normales; los de
        # depuración de verdad empiezan por "[debug] ".
        if mensaje.startswith("[debug] "):
            self._enviar("depuracion", mensaje[len("[debug] "):])
        else:
            self._enviar("info", mensaje)

    def info(self, mensaje):
        self._enviar("info", mensaje)

    def warning(self, mensaje):
        self.avisos.append(str(mensaje))
        self._enviar("aviso", mensaje)

    def error(self, mensaje):
        self._enviar("error", mensaje)


def _respuesta_ok(datos) -> str:
    return json.dumps({"ok": True, "datos": datos}, ensure_ascii=False)


def _respuesta_error(codigo: str, mensaje: str, detalle: str | None = None) -> str:
    return json.dumps({"ok": False, "error": {"codigo": codigo, "mensaje": mensaje, "detalle": detalle}},
                      ensure_ascii=False)


def _es_cancelacion(exc) -> bool:
    """True si la excepción (o una que lleve dentro) es DownloadCancelled de yt-dlp."""
    pendientes, vistos = [exc], set()
    while pendientes:
        actual = pendientes.pop()
        if actual is None or id(actual) in vistos:
            continue
        vistos.add(id(actual))
        if any(clase.__name__ == "DownloadCancelled" for clase in type(actual).__mro__):
            return True
        info = getattr(actual, "exc_info", None)
        if isinstance(info, tuple) and len(info) > 1:
            pendientes.append(info[1])
        pendientes += [actual.__cause__, actual.__context__]
    return False


def _expuesta(funcion):
    """Convierte una función (peticion: dict, emisor) -> datos en una función del puente.

    Nunca deja escapar una excepción hacia C: todo error vuelve como JSON.
    """
    @functools.wraps(funcion)
    def envoltura(peticion_json: str, direccion: int = 0, contexto: int = 0) -> str:
        emisor = Emisor(direccion, contexto)
        try:
            peticion = json.loads(peticion_json or "{}")
        except ValueError as exc:
            return _respuesta_error("interno", f"Petición no válida: {exc}")
        try:
            return _respuesta_ok(funcion(peticion, emisor))
        except Exception as exc:
            if _es_cancelacion(exc):
                emisor.log("info", f"{funcion.__name__}: cancelado por el usuario")
                return _respuesta_error("cancelado", "Cancelado por el usuario")
            mensaje = str(exc).removeprefix("ERROR: ").strip()
            detalle = "".join(traceback.format_exception(exc))
            # Solo los errores de yt-dlp se clasifican por su texto; el resto es un fallo nuestro.
            codigo = errores.clasificar(mensaje) if type(exc).__module__.startswith("yt_dlp") else "interno"
            emisor.log("error", f"{funcion.__name__}: {mensaje}")
            return _respuesta_error(codigo, mensaje, detalle)
    return envoltura


@_expuesta
def version(peticion: dict, emisor: Emisor) -> dict:
    """Versiones de Python, yt-dlp y yt-dlp-ejs (para Ajustes)."""
    import yt_dlp
    import yt_dlp.version
    try:
        import yt_dlp_ejs
        ejs = getattr(yt_dlp_ejs, "version", None)
    except ImportError:
        ejs = None
    return {
        "python": platform.python_version(),
        "yt_dlp": yt_dlp.version.__version__,
        "yt_dlp_ejs": ejs,
        "ruta_yt_dlp": os.path.dirname(yt_dlp.__file__),
    }


def _miniatura(info: dict):
    if info.get("thumbnail"):
        return info["thumbnail"]
    miniaturas = [m for m in info.get("thumbnails") or [] if m.get("url")]
    return miniaturas[-1]["url"] if miniaturas else None


def _opciones_comunes(peticion: dict, registro: _RegistroYtDlp) -> dict:
    """Opciones de YoutubeDL compartidas por info y descargar."""
    opciones = {
        "logger": registro,
        "quiet": True,
        "noprogress": True,
        "noplaylist": True,
        "socket_timeout": 20,
        "extractor_retries": 2,
        "cachedir": peticion.get("cache") or False,
        # Solo para los tests (archivos locales); nunca desde la interfaz.
        "enable_file_urls": bool(peticion.get("permitir_archivos")),
    }
    # Cookies del usuario (cookies.txt importado en Ajustes) para videos que piden su sesión.
    cookies = peticion.get("cookies")
    if cookies and os.path.isfile(cookies):
        opciones["cookiefile"] = cookies
    return opciones


def _primera_entrada(datos: dict, registro: _RegistroYtDlp) -> dict:
    """Si el enlace es una publicación con varios videos (Instagram), usa el primero."""
    if datos.get("_type") != "playlist":
        return datos
    import yt_dlp
    entradas = [e for e in datos.get("entries") or [] if e]
    if not entradas:
        raise yt_dlp.utils.DownloadError("Unsupported URL: la publicación no contiene videos")
    if len(entradas) > 1:
        registro.avisos.append(f"La publicación tiene {len(entradas)} videos; se usa el primero.")
    return entradas[0]


@_expuesta
def info(peticion: dict, emisor: Emisor) -> dict:
    """Analiza un enlace: título, autor, duración, miniatura y opciones por calidad.

    Petición: {"url": str, "cache": str | None, "permitir_archivos": bool}
    """
    import yt_dlp

    registro = _RegistroYtDlp(emisor)
    with yt_dlp.YoutubeDL(dict(_opciones_comunes(peticion, registro), skip_download=True)) as ydl:
        bruto = _primera_entrada(ydl.extract_info(peticion["url"], download=False), registro)
        datos = ydl.sanitize_info(bruto)
    _guardar_analisis(peticion["url"], bruto)

    return {
        "id": datos.get("id"),
        "titulo": datos.get("title") or datos.get("id") or "Sin título",
        "autor": datos.get("uploader") or datos.get("channel") or datos.get("creator"),
        "duracion": datos.get("duration"),
        "miniatura": _miniatura(datos),
        "extractor": datos.get("extractor_key"),
        "url_pagina": datos.get("webpage_url") or peticion["url"],
        "opciones": seleccion.opciones(datos),
        "avisos": registro.avisos,
    }


class _Progreso:
    """Progress hook de yt-dlp: manda el progreso a Swift (máx. 4 veces por segundo)
    y cancela la descarga si Swift lo pide."""

    INTERVALO = 0.25

    def __init__(self, emisor: Emisor, parte: str, cancelacion: _Cancelacion):
        self.emisor, self.parte, self.cancelacion = emisor, parte, cancelacion
        self._ultimo = 0.0

    def __call__(self, d: dict):
        self.cancelacion.comprobar()  # tras cancelar, todas las llamadas (de todos los hilos) paran
        estado = d.get("status")
        if estado not in ("downloading", "finished"):
            return
        ahora = time.monotonic()
        if estado == "downloading" and ahora - self._ultimo < self.INTERVALO:
            return
        self._ultimo = ahora
        total, estimado = d.get("total_bytes"), False
        if not total and d.get("total_bytes_estimate"):
            total, estimado = d["total_bytes_estimate"], True
        cancelar = self.emisor.emitir({
            "tipo": "progreso",
            "parte": self.parte,
            "estado": "terminado" if estado == "finished" else "descargando",
            "descargado": int(d.get("downloaded_bytes") or 0),
            "total": int(total) if total else None,
            "estimado": estimado,
            "velocidad": d.get("speed"),
            "eta": d.get("eta"),
        })
        if cancelar:
            self.cancelacion.activa = True
            self.cancelacion.comprobar()


@_expuesta
def descargar(peticion: dict, emisor: Emisor) -> dict:
    """Descarga cada parte (video y/o audio) con su format_id, sin unirlas (eso lo hace Swift).

    Petición: {"url", "partes": [{"parte": "video"|"audio", "formato": format_id}],
               "carpeta", "cache", "permitir_archivos"}
    Respuesta: {"archivos": {"video": ruta, "audio": ruta}, "titulo", "id"}
    """
    import yt_dlp

    cancelacion = _Cancelacion()
    registro = _RegistroYtDlp(emisor, cancelacion)
    carpeta = peticion["carpeta"]
    os.makedirs(carpeta, exist_ok=True)
    comunes = _opciones_comunes(peticion, registro)

    # Se analiza una vez (o se reutiliza el análisis reciente) y cada parte se descarga
    # sobre una copia de ese resultado.
    datos = _analisis_reciente(peticion["url"])
    if datos is None:
        with yt_dlp.YoutubeDL(dict(comunes, skip_download=True)) as ydl:
            datos = _primera_entrada(ydl.extract_info(peticion["url"], download=False), registro)
        _guardar_analisis(peticion["url"], datos)
    else:
        emisor.log("info", "Se reutiliza el análisis reciente del enlace")

    archivos = {}
    for parte in peticion["partes"]:
        cancelacion.comprobar()
        nombre, formato = parte["parte"], parte["formato"]
        # El format_id va en el nombre: un .part de otro formato nunca se reanuda por error.
        seguro = re.sub(r"[^A-Za-z0-9_.-]", "_", formato)
        opciones = dict(
            comunes,
            format=formato,
            outtmpl={"default": os.path.join(carpeta, f"{nombre}-{seguro}.%(ext)s")},
            progress_hooks=[_Progreso(emisor, nombre, cancelacion)],
            continuedl=True,  # si se cortó, continúa el .part
            retries=10,
            fragment_retries=10,
            concurrent_fragment_downloads=4,
        )
        emisor.log("info", f"Descargando {nombre} (formato {formato})")
        with yt_dlp.YoutubeDL(opciones) as ydl:
            resultado = ydl.process_ie_result(copy.deepcopy(datos), download=True)
        rutas = [d.get("filepath") for d in resultado.get("requested_downloads") or [] if d.get("filepath")]
        if not rutas:
            raise RuntimeError(f"yt-dlp no devolvió el archivo de {nombre}")
        archivos[nombre] = rutas[0]

    return {"archivos": archivos, "titulo": datos.get("title"), "id": datos.get("id")}


_RE_VERSION = re.compile(r"__version__\s*=\s*'([^']+)'")
_RE_EJS = re.compile(r"VERSION\s*=\s*'([^']+)'")


@_expuesta
def inspeccionar_paquete(peticion: dict, emisor: Emisor) -> dict:
    """Lee qué versión de yt-dlp trae un zipapp o wheel (sin importarlo) y qué yt-dlp-ejs exige.

    Petición: {"ruta": str}. Respuesta: {"yt_dlp", "ejs", "incluye_ejs"}.
    """
    with zipfile.ZipFile(peticion["ruta"]) as paquete:
        nombres = set(paquete.namelist())
        if "yt_dlp/version.py" not in nombres:
            raise ValueError("El archivo no contiene yt-dlp")
        version = _RE_VERSION.search(paquete.read("yt_dlp/version.py").decode("utf-8"))
        info_ejs = "yt_dlp/extractor/youtube/jsc/_builtin/vendor/_info.py"
        ejs = _RE_EJS.search(paquete.read(info_ejs).decode("utf-8")) if info_ejs in nombres else None
        incluye_ejs = any(n.startswith("yt_dlp_ejs/") for n in nombres)
    if not version:
        raise ValueError("No se encontró la versión de yt-dlp")
    return {"yt_dlp": version.group(1), "ejs": ejs.group(1) if ejs else None, "incluye_ejs": incluye_ejs}


@_expuesta
def configurar_js(peticion: dict, emisor: Emisor) -> dict:
    """Recibe de Swift el evaluador de JavaScriptCore y registra el proveedor de YouTube.

    Petición: {"evaluador": dirección de la función C}.
    """
    from . import jsc

    resultado = jsc.configurar(int(peticion.get("evaluador") or 0))
    if resultado["registrado"]:
        emisor.log("info", "Desafíos de YouTube: JavaScriptCore listo")
    else:
        emisor.log("aviso", f"No se pudo registrar JavaScriptCore en yt-dlp: {resultado['error']}")
    return resultado


@_expuesta
def probar_js(peticion: dict, emisor: Emisor) -> dict:
    """Ejecuta un script en JavaScriptCore pasando por todo el puente (para los tests)."""
    from . import jsc

    inicio = time.monotonic()
    salida = jsc.evaluar(peticion["script"])
    return {"salida": salida, "segundos": round(time.monotonic() - inicio, 3)}
