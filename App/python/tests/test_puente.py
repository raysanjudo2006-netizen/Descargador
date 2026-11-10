"""Tests del puente Swift ↔ Python (con un callback ctypes real, como el que pone Swift)."""
import ctypes
import json
import pathlib
import tempfile
import unittest

from descargador import puente

try:
    import yt_dlp  # noqa: F401
    HAY_YT_DLP = True
except ImportError:
    HAY_YT_DLP = False


class Recolector:
    """Callback C que guarda los eventos que manda Python."""

    def __init__(self, cancelar=False):
        self.eventos = []
        self._cancelar = cancelar
        self.funcion = puente.TIPO_CALLBACK(self._recibir)

    def _recibir(self, evento, contexto):
        self.eventos.append(json.loads(evento.decode("utf-8")))
        return 1 if self._cancelar else 0

    @property
    def direccion(self):
        return ctypes.cast(self.funcion, ctypes.c_void_p).value


@unittest.skipUnless(HAY_YT_DLP, "yt-dlp no está en sys.path")
class TestPuente(unittest.TestCase):
    def test_version(self):
        r = json.loads(puente.version("{}", 0, 0))
        self.assertTrue(r["ok"], r)
        self.assertRegex(r["datos"]["python"], r"^3\.\d+")
        self.assertTrue(r["datos"]["yt_dlp"])

    def test_infoDeArchivoLocalConCallback(self):
        # ignore_cleanup_errors: en Windows yt-dlp deja el archivo abierto y no se puede borrar.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            archivo = pathlib.Path(tmp) / "muestra.mp4"
            archivo.write_bytes(b"\x00" * 4096)
            recolector = Recolector()
            peticion = {"url": archivo.as_uri(), "permitir_archivos": True, "cache": str(pathlib.Path(tmp) / "cache")}
            r = json.loads(puente.info(json.dumps(peticion), recolector.direccion, 0))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["datos"]["titulo"], "muestra")
        mejor = r["datos"]["opciones"][0]
        self.assertEqual((mejor["calidad"], mejor["disponible"]), ("mejor", True))
        self.assertTrue(any(e["tipo"] == "log" for e in recolector.eventos), recolector.eventos)

    def test_archivosLocalesBloqueadosPorDefecto(self):
        # ignore_cleanup_errors: en Windows yt-dlp deja el archivo abierto y no se puede borrar.
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            archivo = pathlib.Path(tmp) / "muestra.mp4"
            archivo.write_bytes(b"\x00" * 16)
            r = json.loads(puente.info(json.dumps({"url": archivo.as_uri()}), 0, 0))
        self.assertFalse(r["ok"])
        self.assertIn(r["error"]["codigo"], {"no_soportado", "desconocido", "extractor"})
        self.assertTrue(r["error"]["detalle"])


class TestPuenteSinYtDlp(unittest.TestCase):
    def test_cookiesSoloSiExisteElArchivo(self):
        registro = puente._RegistroYtDlp(puente.Emisor(0, 0))
        with tempfile.TemporaryDirectory() as tmp:
            cookies = pathlib.Path(tmp) / "cookies.txt"
            cookies.write_text("# Netscape HTTP Cookie File", encoding="utf-8")
            con = puente._opciones_comunes({"cookies": str(cookies)}, registro)
            sin = puente._opciones_comunes({"cookies": str(pathlib.Path(tmp) / "no-existe.txt")}, registro)
        self.assertEqual(con["cookiefile"], str(cookies))
        self.assertNotIn("cookiefile", sin)

    def test_peticionInvalidaDevuelveErrorJson(self):
        r = json.loads(puente.info("esto no es json", 0, 0))
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"]["codigo"], "interno")

    def test_emisorSinCallbackNoFalla(self):
        self.assertFalse(puente.Emisor(0, 0).emitir({"tipo": "log"}))

    def test_emisorDevuelveCancelacion(self):
        recolector = Recolector(cancelar=True)
        self.assertTrue(puente.Emisor(recolector.direccion, 0).emitir({"tipo": "progreso"}))


if __name__ == "__main__":
    unittest.main()
