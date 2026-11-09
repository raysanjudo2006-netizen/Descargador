"""Tests de la selección de formatos por calidad."""
import unittest

from descargador import seleccion


def fmt(fid, ext="mp4", vcodec="avc1.640028", acodec="none", height=None, width=None,
        protocol="https", filesize=None, tbr=None, abr=None, **extra):
    """Crea un formato al estilo de yt-dlp."""
    d = {"format_id": fid, "ext": ext, "vcodec": vcodec, "acodec": acodec, "height": height,
         "width": width, "protocol": protocol, "filesize": filesize, "tbr": tbr, "abr": abr}
    d.update(extra)
    return d


def audio(fid="140", ext="m4a", acodec="mp4a.40.2", filesize=3_000_000, **extra):
    return fmt(fid, ext=ext, vcodec="none", acodec=acodec, filesize=filesize, **extra)


def por_calidad(info):
    return {o["calidad"]: o for o in seleccion.opciones(info)}


class TestSeleccion(unittest.TestCase):
    def test_ordenYClavesDeLasOpciones(self):
        info = {"formats": [fmt("22", acodec="mp4a.40.2", height=720, width=1280, filesize=10)]}
        opciones = seleccion.opciones(info)
        self.assertEqual([o["calidad"] for o in opciones], ["mejor", "1080", "720", "480", "360", "audio"])
        self.assertEqual(set(opciones[0]), {"calidad", "disponible", "resolucion", "video", "audio", "unir",
                                            "bytes", "aproximado", "protocolo", "extraer_audio"})

    def test_videoYAudioSeparadosSeUnen(self):
        info = {"duration": 60, "formats": [
            fmt("137", height=1080, width=1920, filesize=50_000_000),
            fmt("136", height=720, width=1280, filesize=20_000_000),
            audio("140"),
        ]}
        o = por_calidad(info)
        self.assertEqual((o["mejor"]["video"], o["mejor"]["audio"], o["mejor"]["unir"]), ("137", "140", True))
        self.assertEqual(o["mejor"]["bytes"], 53_000_000)
        self.assertFalse(o["mejor"]["aproximado"])
        self.assertEqual(o["720"]["video"], "136")
        self.assertTrue(o["1080"]["disponible"])
        self.assertFalse(o["480"]["disponible"])

    def test_progresivoPreferidoAIgualResolucion(self):
        info = {"formats": [
            fmt("136", height=720, width=1280, filesize=20),
            fmt("22", acodec="mp4a.40.2", height=720, width=1280, filesize=25),
            audio("140", filesize=3),
        ]}
        o = por_calidad(info)["720"]
        self.assertEqual((o["video"], o["audio"], o["unir"]), ("22", None, False))

    def test_verticalUsaLadoCorto(self):
        info = {"formats": [fmt("v", acodec="aac", height=1920, width=1080, filesize=9)]}
        o = por_calidad(info)
        self.assertEqual(o["1080"]["resolucion"], 1080)
        self.assertTrue(o["1080"]["disponible"])

    def test_httpsAntesQueM3u8(self):
        info = {"formats": [
            fmt("hls-720", acodec="mp4a.40.2", height=720, width=1280, protocol="m3u8_native", tbr=2000),
            fmt("http-720", acodec="mp4a.40.2", height=720, width=1280, protocol="https", tbr=1500),
        ]}
        self.assertEqual(por_calidad(info)["720"]["video"], "http-720")

    def test_mp4DirectoSinMetadatos(self):
        info = {"formats": [fmt("mp4", vcodec=None, acodec=None, protocol="file")]}
        o = por_calidad(info)
        self.assertTrue(o["mejor"]["disponible"])
        self.assertEqual(o["mejor"]["video"], "mp4")
        for calidad in ("1080", "720", "480", "360"):
            self.assertFalse(o[calidad]["disponible"], calidad)
        self.assertTrue(o["audio"]["disponible"])
        self.assertTrue(o["audio"]["extraer_audio"])

    def test_formatoUnicoSinListaDeFormatos(self):
        info = {"url": "https://x/v.mp4", "ext": "mp4", "format_id": "0", "height": 480, "width": 854}
        self.assertTrue(por_calidad(info)["480"]["disponible"])

    def test_codecsIncompatiblesSeDescartan(self):
        info = {"formats": [
            fmt("vp9", ext="webm", vcodec="vp9", height=1080, width=1920),
            fmt("av1", vcodec="av01.0.08M.08", height=1080, width=1920),
            fmt("hev1", vcodec="hev1.1.6.L120.90", acodec="mp4a.40.2", height=1080, width=1920),
            fmt("tiktok", vcodec="bytevc1", acodec="aac", height=1080, width=1920),
            audio("251", ext="webm", acodec="opus"),
        ]}
        o = por_calidad(info)
        self.assertFalse(o["mejor"]["disponible"])
        self.assertFalse(o["audio"]["disponible"])

    def test_hevcConEtiquetaHvc1EsCompatible(self):
        info = {"formats": [fmt("h", vcodec="hvc1.1.6.L120.90", acodec="mp4a.40.2", height=1080, width=1920)]}
        self.assertEqual(por_calidad(info)["1080"]["video"], "h")

    def test_tamanoEstimadoConTbrEsAproximado(self):
        info = {"duration": 100, "formats": [fmt("22", acodec="mp4a.40.2", height=720, width=1280, tbr=800)]}
        o = por_calidad(info)["720"]
        self.assertEqual(o["bytes"], 10_000_000)  # 800 kbps × 100 s / 8
        self.assertTrue(o["aproximado"])

    def test_tamanoDesconocido(self):
        info = {"formats": [fmt("22", acodec="mp4a.40.2", height=720, width=1280)]}
        o = por_calidad(info)["720"]
        self.assertIsNone(o["bytes"])

    def test_audioSueltoPreferido(self):
        info = {"formats": [
            fmt("22", acodec="mp4a.40.2", height=720, width=1280, filesize=20),
            audio("139", filesize=1, abr=48),
            audio("140", filesize=3, abr=128),
        ]}
        o = por_calidad(info)["audio"]
        self.assertEqual((o["audio"], o["video"], o["extraer_audio"]), ("140", None, False))
        self.assertEqual(o["bytes"], 3)

    def test_audioSinPistaSueltaSeExtraeDelVideoMasLigero(self):
        info = {"formats": [
            fmt("hd", acodec="mp4a.40.2", height=720, width=1280, filesize=20),
            fmt("sd", acodec="mp4a.40.2", height=360, width=640, filesize=5),
        ]}
        o = por_calidad(info)["audio"]
        self.assertEqual((o["video"], o["extraer_audio"], o["bytes"]), ("sd", True, 5))

    def test_sinFormatos(self):
        o = por_calidad({"formats": []})
        self.assertFalse(any(x["disponible"] for x in o.values()))


if __name__ == "__main__":
    unittest.main()
