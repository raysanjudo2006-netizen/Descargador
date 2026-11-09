#!/usr/bin/env python3
"""Extrae las capturas (adjuntos PNG) de un .xcresult y les pone el nombre del adjunto.

Uso: python3 scripts/ci/exportar_capturas.py build/Resultados.xcresult build/capturas

Usa `xcrun xcresulttool export attachments` (Xcode 16+), que deja los archivos con
nombres UUID y un manifest.json; aquí se renombran a "01-descargar-claro.png", etc.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# "01-descargar-claro_0_1A2B3C4D-....png" -> "01-descargar-claro"
SUFIJO_XCODE = re.compile(r"_\d+_[0-9A-Fa-f-]{36}$")


def adjuntos(nodo):
    """Recorre el manifest y devuelve cada dict que describe un archivo exportado."""
    if isinstance(nodo, dict):
        if "exportedFileName" in nodo:
            yield nodo
        for valor in nodo.values():
            yield from adjuntos(valor)
    elif isinstance(nodo, list):
        for valor in nodo:
            yield from adjuntos(valor)


def nombre_legible(adjunto) -> str:
    bruto = adjunto.get("suggestedHumanReadableName") or adjunto.get("name") or adjunto["exportedFileName"]
    base = pathlib.Path(bruto).stem
    return SUFIJO_XCODE.sub("", base) or pathlib.Path(adjunto["exportedFileName"]).stem


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    xcresult, destino = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    if not xcresult.exists():
        print(f"::warning::No existe {xcresult}; no hay capturas que exportar.")
        return 0
    destino.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        proceso = subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(xcresult), "--output-path", str(tmp)],
            capture_output=True, text=True)
        if proceso.returncode != 0:
            print(f"::warning::xcresulttool no pudo exportar adjuntos: {proceso.stderr.strip()}")
            return 0

        manifest = tmp / "manifest.json"
        usados: set[str] = set()
        copiados = 0
        if manifest.exists():
            for adjunto in adjuntos(json.loads(manifest.read_text())):
                origen = tmp / adjunto["exportedFileName"]
                if origen.suffix.lower() != ".png" or not origen.exists():
                    continue
                nombre = nombre_legible(adjunto)
                while nombre in usados:  # evita pisar capturas con el mismo nombre
                    nombre += "-bis"
                usados.add(nombre)
                shutil.copy(origen, destino / f"{nombre}.png")
                copiados += 1
        else:
            for origen in tmp.glob("*.png"):
                shutil.copy(origen, destino / origen.name)
                copiados += 1

    print(f"Capturas exportadas: {copiados}")
    for archivo in sorted(destino.glob("*.png")):
        print(f"  - {archivo.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
