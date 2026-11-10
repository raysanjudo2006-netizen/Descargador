"""Desafíos JavaScript de YouTube resueltos con JavaScriptCore (el motor JS de iOS).

yt-dlp necesita ejecutar JavaScript para resolver los desafíos "n" y "sig" de YouTube.
Normalmente lanza deno/node/quickjs como procesos, pero iOS no deja lanzar procesos.
Aquí se registra un proveedor propio (subclase de EJSBaseJCP, el mismo mecanismo que usa
el plugin yt-dlp-apple-webkit-jsi en a-Shell) que, en vez de un proceso, llama a Swift:
Swift ejecuta el script con JavaScriptCore y devuelve lo que imprimió con console.log.

EJSBaseJCP es API interna de yt-dlp: si una versión futura la cambia, el registro falla
sin romper el resto (YouTube funcionaría sin desafíos, con menos formatos).
"""
from __future__ import annotations

import ctypes
import time

# void responder(const char *texto, void *contexto)
TIPO_RESPUESTA = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_void_p)
# int evaluador(const char *script, responder, void *contexto)
TIPO_EVALUADOR = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_char_p, TIPO_RESPUESTA, ctypes.c_void_p)

_evaluador = None
_registrado = False
_error_registro: str | None = None


def configurar(direccion: int) -> dict:
    """Guarda el evaluador que ofrece Swift y registra el proveedor en yt-dlp."""
    global _evaluador
    _evaluador = TIPO_EVALUADOR(direccion) if direccion else None
    return {"disponible": _evaluador is not None, "registrado": _registrar(), "error": _error_registro}


def evaluar(script: str) -> str:
    """Ejecuta JavaScript en JavaScriptCore y devuelve lo que imprimió con console.log."""
    if _evaluador is None:
        raise RuntimeError("JavaScriptCore no está configurado")
    resultado: list[str] = []

    @TIPO_RESPUESTA
    def responder(texto, _contexto):
        resultado.append(texto.decode("utf-8", "replace") if texto else "")

    codigo = _evaluador(script.encode("utf-8"), responder, None)
    salida = resultado[0] if resultado else ""
    if codigo != 0:
        raise RuntimeError(salida or "error desconocido de JavaScriptCore")
    return salida


def _registrar() -> bool:
    """Registra el proveedor una sola vez (yt-dlp no admite registrar dos veces)."""
    global _registrado, _error_registro
    if _registrado:
        return True
    try:
        from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
        from yt_dlp.extractor.youtube.jsc.provider import (
            JsChallengeProviderError,
            register_preference,
            register_provider,
        )
    except Exception as exc:  # versión de yt-dlp sin esta API
        _error_registro = f"{type(exc).__name__}: {exc}"
        return False

    @register_provider
    class JavaScriptCoreJCP(EJSBaseJCP):
        PROVIDER_NAME = "javascriptcore"
        PROVIDER_VERSION = "1.0.0"
        BUG_REPORT_LOCATION = "la pestaña Registro de Descargador"
        JS_RUNTIME_NAME = "javascriptcore"

        def is_available(self) -> bool:
            # No hay ejecutable que buscar: basta con que Swift haya dado el evaluador.
            return _evaluador is not None and self._available

        def _run_js_runtime(self, stdin: str) -> str:
            inicio = time.monotonic()
            try:
                salida = evaluar(stdin)
            except RuntimeError as exc:
                raise JsChallengeProviderError(f"JavaScriptCore: {exc}") from exc
            self.logger.info(f"Desafío de YouTube resuelto con JavaScriptCore en {time.monotonic() - inicio:.1f} s")
            return salida

    @register_preference(JavaScriptCoreJCP)
    def _preferencia(provider, requests) -> int:
        return 1000

    _registrado = True
    return True
