"""Puente entre Swift y yt-dlp.

Swift (a través de PuentePython.c) llama a estas funciones con tres argumentos:
    funcion(peticion_json: str, direccion_callback: int, contexto: int) -> str (JSON)

- La respuesta siempre es JSON: {"ok": true, "datos": …} o {"ok": false, "error": {…}}.
- Los eventos (registro y, más adelante, progreso) se envían a Swift por un callback C
  `int callback(const char *evento_json, void *contexto)`; si devuelve 1, Swift pide cancelar.
"""
from __future__ import annotations

import ctypes
import functools
import json
import os
import platform
import traceback

from . import errores, seleccion

TIPO_CALLBACK = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p)


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


class _RegistroYtDlp:
    """Logger para yt-dlp: reenvía todo al Registro de la app y guarda los avisos."""

    def __init__(self, emisor: Emisor):
        self.emisor = emisor
        self.avisos: list[str] = []

    def debug(self, mensaje):
        # Con un logger, yt-dlp manda aquí también los mensajes normales; los de
        # depuración de verdad empiezan por "[debug] ".
        if mensaje.startswith("[debug] "):
            self.emisor.log("depuracion", mensaje[len("[debug] "):])
        else:
            self.emisor.log("info", mensaje)

    def info(self, mensaje):
        self.emisor.log("info", mensaje)

    def warning(self, mensaje):
        self.avisos.append(str(mensaje))
        self.emisor.log("aviso", mensaje)

    def error(self, mensaje):
        self.emisor.log("error", mensaje)


def _respuesta_ok(datos) -> str:
    return json.dumps({"ok": True, "datos": datos}, ensure_ascii=False)


def _respuesta_error(codigo: str, mensaje: str, detalle: str | None = None) -> str:
    return json.dumps({"ok": False, "error": {"codigo": codigo, "mensaje": mensaje, "detalle": detalle}},
                      ensure_ascii=False)


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


@_expuesta
def info(peticion: dict, emisor: Emisor) -> dict:
    """Analiza un enlace: título, autor, duración, miniatura y opciones por calidad.

    Petición: {"url": str, "cache": str | None, "permitir_archivos": bool}
    """
    import yt_dlp

    registro = _RegistroYtDlp(emisor)
    opciones_ydl = {
        "logger": registro,
        "quiet": True,
        "noprogress": True,
        "noplaylist": True,
        "skip_download": True,
        "socket_timeout": 20,
        "extractor_retries": 2,
        "cachedir": peticion.get("cache") or False,
        # Solo para los tests (archivos locales); nunca desde la interfaz.
        "enable_file_urls": bool(peticion.get("permitir_archivos")),
    }
    with yt_dlp.YoutubeDL(opciones_ydl) as ydl:
        datos = ydl.sanitize_info(ydl.extract_info(peticion["url"], download=False))

    if datos.get("_type") == "playlist":
        entradas = [e for e in datos.get("entries") or [] if e]
        if not entradas:
            raise yt_dlp.utils.DownloadError("Unsupported URL: la publicación no contiene videos")
        if len(entradas) > 1:
            registro.avisos.append(f"La publicación tiene {len(entradas)} videos; se usa el primero.")
        datos = entradas[0]

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
