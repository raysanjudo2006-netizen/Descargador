"""Tests del proveedor de desafíos JS (con un evaluador falso en lugar de JavaScriptCore)."""
import ctypes
import json
import unittest

from descargador import jsc, puente
from test_puente import HAY_YT_DLP


@jsc.TIPO_EVALUADOR
def _evaluador_falso(script, responder, contexto):
    """Imita a Swift: devuelve "eco:<script>" o un error si el script contiene "fallo"."""
    texto = script.decode("utf-8")
    if "fallo" in texto:
        responder(b"ReferenceError: x is not defined", contexto)
        return 1
    responder(("eco:" + texto).encode("utf-8"), contexto)
    return 0


DIRECCION = ctypes.cast(_evaluador_falso, ctypes.c_void_p).value


class TestJsc(unittest.TestCase):
    def setUp(self):
        jsc.configurar(DIRECCION)

    def test_evaluarDevuelveLaSalida(self):
        self.assertEqual(jsc.evaluar("1+1"), "eco:1+1")

    def test_errorDeJavaScript(self):
        with self.assertRaises(RuntimeError) as contexto:
            jsc.evaluar("fallo()")
        self.assertIn("ReferenceError", str(contexto.exception))

    def test_sinEvaluadorNoSePuedeEvaluar(self):
        jsc.configurar(0)
        with self.assertRaises(RuntimeError):
            jsc.evaluar("1")

    def test_probarJsPasaPorElPuente(self):
        r = json.loads(puente.probar_js(json.dumps({"script": "abc"}), 0, 0))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["datos"]["salida"], "eco:abc")

    @unittest.skipUnless(HAY_YT_DLP, "yt-dlp no está en sys.path")
    def test_proveedorRegistradoEnYtDlp(self):
        r = json.loads(puente.configurar_js(json.dumps({"evaluador": DIRECCION}), 0, 0))
        self.assertTrue(r["ok"], r)
        self.assertTrue(r["datos"]["registrado"], r)
        from yt_dlp.extractor.youtube.jsc._registry import _jsc_providers
        proveedor = _jsc_providers.value["JavaScriptCore"]
        self.assertEqual(proveedor.PROVIDER_NAME, "javascriptcore")
        self.assertEqual(proveedor.JS_RUNTIME_NAME, "javascriptcore")


if __name__ == "__main__":
    unittest.main()
