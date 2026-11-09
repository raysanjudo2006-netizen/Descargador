"""Elige qué formatos descargar para cada calidad.

Sin ffmpeg no se puede recodificar: solo valen formatos que Fotos acepta tal cual
(video H.264 o HEVC "hvc1" en MP4/MOV y audio AAC en M4A/MP4). Si el video y el audio
vienen separados, la app los une después con AVFoundation (sin recodificar).

La "resolución" es el lado corto del video, como hace yt-dlp: un TikTok vertical de
1080x1920 cuenta como 1080p.
"""
from __future__ import annotations

# Calidades de video en el orden en que se muestran; None = sin límite ("Mejor").
CALIDADES_VIDEO = (("mejor", None), ("1080", 1080), ("720", 720), ("480", 480), ("360", 360))

# Una calidad solo está "disponible" si lo elegido supera la calidad inferior;
# si para 1080p lo mejor es 720p, el botón de 1080p se desactiva.
_UMBRAL_INFERIOR = {"1080": 720, "720": 480, "480": 360, "360": 0}

_VIDEO_COMPATIBLE = ("avc1", "avc3", "h264", "hvc1", "hevc", "h265")
_AUDIO_COMPATIBLE = ("mp4a", "aac")
_CONTENEDOR_VIDEO = ("mp4", "m4v", "mov")
_CONTENEDOR_AUDIO = ("m4a", "mp4")
# Preferencia por protocolo: descarga directa > HLS/DASH por fragmentos. Otros no se usan.
_PROTOCOLOS = {"https": 2, "http": 2, "file": 2, "m3u8_native": 1, "m3u8": 1, "http_dash_segments": 1}


def _codec(valor):
    """Códec en minúsculas; None si yt-dlp no lo sabe; "none" si no hay esa pista."""
    return None if valor is None else str(valor).lower()


def _rango_protocolo(f) -> int:
    return _PROTOCOLOS.get(f.get("protocol") or "https", 0)


def _video_compatible(f) -> bool:
    if f.get("ext") not in _CONTENEDOR_VIDEO or _rango_protocolo(f) == 0:
        return False
    vcodec = _codec(f.get("vcodec"))
    if vcodec == "none":
        return False
    return vcodec is None or vcodec.startswith(_VIDEO_COMPATIBLE)


def _audio_de_progresivo_compatible(f) -> bool:
    acodec = _codec(f.get("acodec"))
    return acodec is None or acodec.startswith(_AUDIO_COMPATIBLE)


def _solo_audio(f) -> bool:
    acodec = _codec(f.get("acodec"))
    return (_codec(f.get("vcodec")) == "none" and acodec not in (None, "none")
            and acodec.startswith(_AUDIO_COMPATIBLE) and f.get("ext") in _CONTENEDOR_AUDIO
            and _rango_protocolo(f) > 0)


def _resolucion(f):
    ancho, alto = f.get("width"), f.get("height")
    if ancho and alto:
        return min(ancho, alto)
    return alto or None


def _tamano(f, duracion):
    """(bytes, aproximado). Usa filesize, luego filesize_approx, luego tbr × duración."""
    if f.get("filesize"):
        return int(f["filesize"]), False
    if f.get("filesize_approx"):
        return int(f["filesize_approx"]), True
    tasa = f.get("tbr") or f.get("abr")
    if tasa and duracion:
        return int(tasa * 1000 / 8 * duracion), True
    return None, True


def _bitrate(f) -> float:
    return f.get("tbr") or f.get("abr") or 0


class _Candidato:
    """Un video progresivo, o un video sin audio emparejado con el mejor audio suelto."""

    def __init__(self, video, audio=None):
        self.video, self.audio = video, audio
        self.resolucion = _resolucion(video)
        rangos = [_rango_protocolo(video)] + ([_rango_protocolo(audio)] if audio else [])
        self.rango = min(rangos)
        self.progresivo = audio is None
        self.bitrate = _bitrate(video) + (_bitrate(audio) if audio else 0)

    def clave(self):
        # Más resolución > mejor protocolo > sin unir > más bitrate.
        return (self.resolucion or 0, self.rango, self.progresivo, self.bitrate)


def _candidatos(formatos):
    progresivos = [f for f in formatos if _video_compatible(f)
                   and _codec(f.get("acodec")) != "none" and _audio_de_progresivo_compatible(f)]
    solo_video = [f for f in formatos if _video_compatible(f) and _codec(f.get("acodec")) == "none"]
    audios = [f for f in formatos if _solo_audio(f)]
    mejor_audio = max(audios, key=lambda a: (_rango_protocolo(a), _bitrate(a)), default=None)
    candidatos = [_Candidato(f) for f in progresivos]
    if mejor_audio is not None:
        candidatos += [_Candidato(f, mejor_audio) for f in solo_video]
    return candidatos, progresivos, mejor_audio


def _opcion(calidad, disponible=False, video=None, audio=None, duracion=None,
            resolucion=None, extraer_audio=False):
    partes = [p for p in (video, audio) if p is not None]
    tamanos = [_tamano(p, duracion) for p in partes]
    if tamanos and all(t[0] is not None for t in tamanos):
        total, aproximado = sum(t[0] for t in tamanos), any(t[1] for t in tamanos)
    else:
        total, aproximado = None, True
    principal = video or audio
    return {
        "calidad": calidad,
        "disponible": disponible,
        "resolucion": resolucion,
        "video": video.get("format_id") if video else None,
        "audio": audio.get("format_id") if audio else None,
        "unir": video is not None and audio is not None,
        "bytes": total,
        "aproximado": aproximado,
        "protocolo": principal.get("protocol") if principal else None,
        "extraer_audio": extraer_audio,
    }


def opciones(info: dict) -> list[dict]:
    """Una opción por calidad: mejor, 1080, 720, 480, 360 y audio."""
    formatos = info.get("formats") or ([info] if info.get("url") else [])
    duracion = info.get("duration")
    candidatos, progresivos, mejor_audio = _candidatos(formatos)
    resultado = []

    for calidad, maximo in CALIDADES_VIDEO:
        if maximo is None:
            grupo = candidatos
        else:
            grupo = [c for c in candidatos if c.resolucion is not None and c.resolucion <= maximo]
        if not grupo:
            resultado.append(_opcion(calidad))
            continue
        elegido = max(grupo, key=_Candidato.clave)
        disponible = maximo is None or (elegido.resolucion or 0) > _UMBRAL_INFERIOR[calidad]
        resultado.append(_opcion(calidad, disponible, elegido.video, elegido.audio, duracion,
                                 elegido.resolucion))

    if mejor_audio is not None:
        resultado.append(_opcion("audio", True, audio=mejor_audio, duracion=duracion))
    elif progresivos:
        # Sin pista de audio suelta: se descarga el video más ligero y se extrae su audio.
        def peso(f):
            bytes_, _ = _tamano(f, duracion)
            return (-_rango_protocolo(f), bytes_ if bytes_ is not None else float("inf"))
        ligero = min(progresivos, key=peso)
        resultado.append(_opcion("audio", True, video=ligero, duracion=duracion, extraer_audio=True))
    else:
        resultado.append(_opcion("audio"))
    return resultado
