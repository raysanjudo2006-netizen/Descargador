#!/usr/bin/env python3
"""Ejecuta los tests del código Python de la app (sin iPhone ni Mac).

Uso:  python scripts/probar_python.py

Si yt-dlp no está instalado, los tests que lo necesitan se saltan. Para usar wheels ya
descargados sin instalarlos, indica sus rutas en DESCARGADOR_RUTAS_EXTRA separadas
por ';' en Windows o ':' en macOS/Linux.
"""
import os
import pathlib
import sys
import unittest

RAIZ = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    extra = [r for r in os.environ.get("DESCARGADOR_RUTAS_EXTRA", "").split(os.pathsep) if r]
    sys.path[:0] = [str(RAIZ / "App/python/app"), *extra]
    pruebas = RAIZ / "App/python/tests"
    suite = unittest.defaultTestLoader.discover(str(pruebas), top_level_dir=str(pruebas))
    resultado = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if resultado.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
