"""Tests de la clasificación de errores de yt-dlp."""
import unittest

from descargador.errores import clasificar


class TestErrores(unittest.TestCase):
    def comprobar(self, codigo, *mensajes):
        for mensaje in mensajes:
            self.assertEqual(clasificar(mensaje), codigo, mensaje)

    def test_redAntesQueExtractor(self):
        self.comprobar(
            "sin_conexion",
            "ERROR: [generic] Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>",
            "ERROR: Unable to download webpage: The read operation timed out",
            "ERROR: [youtube] abc: Unable to download API page: <urlopen error [Errno 50] Network is down>",
            "The Internet connection appears to be offline.",
        )

    def test_privado(self):
        self.comprobar("privado", "ERROR: [youtube] abc: Private video. Sign in if you've been granted access",
                       "ERROR: [instagram] xyz: This account is private")

    def test_requiereSesion(self):
        self.comprobar(
            "requiere_sesion",
            "ERROR: [youtube] abc: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies",
            "ERROR: [instagram] xyz: Requested content is not available, rate-limit reached or login required",
            "ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users.",
        )

    def test_geo(self):
        self.comprobar("geo", "ERROR: [youtube] abc: The uploader has not made this video available in your country")

    def test_noDisponible(self):
        self.comprobar("no_disponible", "ERROR: [youtube] abc: Video unavailable. This video has been removed by the uploader",
                       "ERROR: [generic] x: Unable to download webpage: HTTP Error 404: Not Found")

    def test_noSoportado(self):
        self.comprobar("no_soportado", "ERROR: Unsupported URL: https://example.com/")

    def test_extractor(self):
        self.comprobar("extractor", "ERROR: [tiktok] 123: Unable to extract universal data; please report this issue",
                       "ERROR: [youtube] abc: Requested format is not available")

    def test_desconocido(self):
        self.comprobar("desconocido", "algo raro", "", None)


if __name__ == "__main__":
    unittest.main()
