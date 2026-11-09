#!/usr/bin/env python3
"""Elige un simulador de iPhone para los tests e imprime su UDID.

Preferencia: iOS 18 (lo más parecido al iOS 17 del iPhone real que ofrece GitHub);
si no hay, el iOS más antiguo disponible. Dentro de esa versión, "iPhone 16".

Uso: xcrun simctl list devices available -j | python3 scripts/ci/elegir_simulador.py
"""
import json
import sys


def version_de(runtime: str):
    # "com.apple.CoreSimulator.SimRuntime.iOS-18-5" -> (18, 5)
    try:
        return tuple(int(x) for x in runtime.split(".iOS-")[1].split("-"))
    except (IndexError, ValueError):
        return None


def main() -> int:
    dispositivos = json.load(sys.stdin)["devices"]
    candidatos = []
    for runtime, lista in dispositivos.items():
        version = version_de(runtime)
        if version is None:
            continue
        for d in lista:
            if d.get("isAvailable", True) and d["name"].startswith("iPhone"):
                candidatos.append((version, d["name"], d["udid"]))

    if not candidatos:
        print("No hay simuladores de iPhone disponibles", file=sys.stderr)
        return 1

    ios18 = [c for c in candidatos if c[0][0] == 18]
    grupo = ios18 or candidatos
    elegido = sorted(grupo, key=lambda c: (c[0], c[1] != "iPhone 16", c[1]))[0]
    version = ".".join(str(x) for x in elegido[0])
    print(f"Simulador elegido: {elegido[1]} (iOS {version})", file=sys.stderr)
    print(elegido[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())
