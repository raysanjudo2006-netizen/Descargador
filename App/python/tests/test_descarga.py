"""Tests de descargar e inspeccionar_paquete del puente."""
import io
import json
import pathlib
import tempfile
import unittest
import zipfile

from descargador import puente
from test_puente import HAY_YT_DLP, Recolector


@unittest.skipUnless(HAY_YT_DLP, "yt-dlp no está en sys.path")
class TestDescargar(unittest.TestCase):
    def _peticion(self, tmp, archivo):
        return {
            "url": archivo.as_uri(),
            "partes": [{"parte": "video", "formato": "mp4"}],
            "carpeta": str(pathlib.Path(tmp) / "salida"),
            "cache": str(pathlib.Path(tmp) / "cache"),
            "permitir_archivos": True,
        }

    def test_descargaArchivoLocalConProgreso(self):
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            archivo = pathlib.Path(tmp) / "muestra.mp4"
            archivo.write_bytes(b"\x01" * 500_000)
            recolector = Recolector()
            r = json.loads(puente.descargar(json.dumps(self._peticion(tmp, archivo)), recolector.direccion, 0))
            self.assertTrue(r["ok"], r)
            ruta = pathlib.Path(r["datos"]["archivos"]["video"])
            self.assertTrue(ruta.exists())
            # El format_id va en el nombre para no reanudar un .part de otro formato.
            self.assertEqual(ruta.name, "video-mp4.mp4")
            self.assertEqual(ruta.stat().st_size, 500_000)
            self.assertEqual(r["datos"]["titulo"], "muestra")
        progreso = [e for e in recolector.eventos if e["tipo"] == "progreso"]
        self.assertTrue(progreso, recolector.eventos)
        self.assertEqual(progreso[-1]["estado"], "terminado")
        self.assertEqual(progreso[-1]["parte"], "video")
        self.assertEqual(progreso[-1]["descargado"], 500_000)

    def test_descargaCancelada(self):
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
            archivo = pathlib.Path(tmp) / "muestra.mp4"
            archivo.write_bytes(b"\x01" * 500_000)
            recolector = Recolector(cancelar=True)
            r = json.loads(puente.descargar(json.dumps(self._peticion(tmp, archivo)), recolector.direccion, 0))
        self.assertFalse(r["ok"])
        self.assertEqual(r["error"]["codigo"], "cancelado")


class TestInspeccionarPaquete(unittest.TestCase):
    def _zipapp(self, carpeta, con_ejs=True):
        """Imita el zipapp `yt-dlp` de GitHub: un zip con una línea #! delante."""
        memoria = io.BytesIO()
        with zipfile.ZipFile(memoria, "w") as z:
            z.writestr("__main__.py", "import yt_dlp\n")
            z.writestr("yt_dlp/version.py", "# generado\n__version__ = '2099.01.02'\nCHANNEL = 'stable'\n")
            z.writestr("yt_dlp/extractor/youtube/jsc/_builtin/vendor/_info.py", "VERSION = '9.9.9'\nHASHES = {}\n")
            if con_ejs:
                z.writestr("yt_dlp_ejs/__init__.py", "")
        ruta = pathlib.Path(carpeta) / "yt-dlp"
        ruta.write_bytes(b"#!/usr/bin/env python3\n" + memoria.getvalue())
        return ruta

    def test_leeVersionesDelZipapp(self):
        with tempfile.TemporaryDirectory() as tmp:
            ruta = self._zipapp(tmp)
            r = json.loads(puente.inspeccionar_paquete(json.dumps({"ruta": str(ruta)}), 0, 0))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["datos"], {"yt_dlp": "2099.01.02", "ejs": "9.9.9", "incluye_ejs": True})

    def test_archivoQueNoEsYtDlp(self):
        with tempfile.TemporaryDirectory() as tmp:
            ruta = pathlib.Path(tmp) / "otro.zip"
            with zipfile.ZipFile(ruta, "w") as z:
                z.writestr("hola.txt", "hola")
            r = json.loads(puente.inspeccionar_paquete(json.dumps({"ruta": str(ruta)}), 0, 0))
        self.assertFalse(r["ok"])


if __name__ == "__main__":
    unittest.main()
