#!/usr/bin/env python3
"""Genera el icono de la app (1024x1024, sin alfa) con Pillow.

Diseño: degradado diagonal naranja → rojo coral con una flecha blanca que
baja hacia una bandeja. Se dibuja a 4x y se reduce para suavizar bordes.

Uso:  python scripts/generar_icono.py
"""
from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

TAM = 1024
ESCALA = 4
COLOR_INICIO = (0xFF, 0x7A, 0x45)  # arriba a la izquierda
COLOR_FIN = (0xE8, 0x36, 0x4F)     # abajo a la derecha
BLANCO = (255, 255, 255)


def degradado(tam: int) -> Image.Image:
    """Degradado diagonal construido a partir de una rampa de 1 píxel de alto."""
    rampa = Image.new("RGB", (2 * tam, 1))
    for x in range(2 * tam):
        t = x / (2 * tam - 1)
        rampa.putpixel((x, 0), tuple(round(a + (b - a) * t) for a, b in zip(COLOR_INICIO, COLOR_FIN)))
    # Estirar la rampa y girarla 45° da un degradado diagonal sin bucles por píxel.
    grande = rampa.resize((2 * tam, 2 * tam)).rotate(-45, resample=Image.BICUBIC)
    desplazamiento = tam // 2
    return grande.crop((desplazamiento, desplazamiento, desplazamiento + tam, desplazamiento + tam))


def main() -> None:
    s = ESCALA
    # El degradado se calcula a tamaño final y se amplía: es suave y ahorra memoria.
    img = degradado(TAM).resize((TAM * s, TAM * s), resample=Image.BICUBIC)
    d = ImageDraw.Draw(img)

    def caja(x0, y0, x1, y1):
        return (x0 * s, y0 * s, x1 * s, y1 * s)

    # Flecha: tallo redondeado + punta triangular.
    d.rounded_rectangle(caja(452, 196, 572, 520), radius=60 * s, fill=BLANCO)
    d.polygon([(292 * s, 470 * s), (732 * s, 470 * s), (512 * s, 690 * s)], fill=BLANCO)

    # Bandeja en forma de U.
    d.rounded_rectangle(caja(236, 748, 788, 828), radius=40 * s, fill=BLANCO)
    d.rounded_rectangle(caja(236, 640, 316, 828), radius=40 * s, fill=BLANCO)
    d.rounded_rectangle(caja(708, 640, 788, 828), radius=40 * s, fill=BLANCO)

    final = img.resize((TAM, TAM), resample=Image.LANCZOS).convert("RGB")
    DESTINO.parent.mkdir(parents=True, exist_ok=True)
    final.save(DESTINO, format="PNG", optimize=True)
    print(f"Icono guardado en {DESTINO.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
