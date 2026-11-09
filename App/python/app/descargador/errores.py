"""Clasifica los mensajes de error de yt-dlp en códigos que Swift traduce al español.

El orden importa: un fallo de red suele llegar envuelto en "Unable to download webpage",
así que la red se comprueba antes que los errores del extractor.
"""
from __future__ import annotations

_REGLAS = (
    ("sin_conexion", (
        "urlopen error", "nodename nor servname", "name or service not known", "failed to resolve",
        "temporary failure in name resolution", "network is unreachable", "network is down",
        "no route to host", "connection refused", "connection reset", "connection aborted",
        "timed out", "internet connection appears to be offline",
    )),
    ("privado", (
        "private video", "video is private", "this account is private", "this video is private",
    )),
    ("requiere_sesion", (
        "sign in to confirm", "login required", "log in to", "login to", "requires authentication",
        "confirm your age", "age-restricted", "age restricted", "--cookies", "not a bot",
    )),
    ("geo", (
        "not available in your country", "available in your country", "geo restrict",
        "geo-restrict", "not available from your location",
    )),
    ("no_disponible", (
        "video unavailable", "has been removed", "no longer available", "does not exist",
        "isn't available", "http error 404",
    )),
    ("no_soportado", ("unsupported url",)),
    ("extractor", (
        "unable to extract", "please report this issue", "nsig extraction failed",
        "signature extraction failed", "no video formats found", "requested format is not available",
        "unable to download", "http error 403",
    )),
)


def clasificar(mensaje) -> str:
    """Devuelve el código del error a partir del mensaje de yt-dlp."""
    texto = (mensaje or "").lower()
    for codigo, claves in _REGLAS:
        if any(clave in texto for clave in claves):
            return codigo
    return "desconocido"
