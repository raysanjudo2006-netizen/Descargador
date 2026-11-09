#!/usr/bin/env python3
"""Comprobaciones estáticas que se pueden ejecutar en Windows, sin Xcode.

No sustituye al compilador (eso solo ocurre en GitHub Actions), pero atrapa
errores tontos antes de gastar una ejecución de CI:

- project.yml y los workflows son YAML válido y las rutas que citan existen.
- Cada Contents.json del catálogo de recursos es JSON válido.
- El icono es 1024x1024 sin canal alfa.
- Cada archivo .swift tiene llaves, paréntesis y corchetes balanceados
  (ignorando cadenas y comentarios).
- Los scripts .sh usan finales de línea LF.

Uso:  python scripts/verificar.py
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CARPETAS_SWIFT = ["App", "Tests", "ShareExtension"]
PARES = {")": "(", "]": "[", "}": "{"}


# ---------------------------------------------------------------------------
# YAML
# ---------------------------------------------------------------------------
def comprobar_yaml(fallos: list[str]) -> None:
    try:
        import yaml  # PyYAML
    except ImportError:
        fallos.append("Falta PyYAML: ejecuta  python -m pip install pyyaml")
        return

    proyecto = RAIZ / "project.yml"
    if not proyecto.exists():
        fallos.append("No existe project.yml")
    else:
        try:
            datos = yaml.safe_load(proyecto.read_text(encoding="utf-8"))
        except yaml.YAMLError as e:
            fallos.append(f"project.yml no es YAML válido: {e}")
            datos = None
        if isinstance(datos, dict):
            for nombre, target in (datos.get("targets") or {}).items():
                for fuente in target.get("sources", []):
                    ruta = fuente["path"] if isinstance(fuente, dict) else fuente
                    if not (RAIZ / ruta).exists():
                        fallos.append(f"project.yml: el target {nombre} cita '{ruta}', que no existe")

    workflows = sorted((RAIZ / ".github" / "workflows").glob("*.yml"))
    if not workflows:
        fallos.append("No hay workflows en .github/workflows")
    for wf in workflows:
        texto = wf.read_text(encoding="utf-8")
        try:
            yaml.safe_load(texto)
        except yaml.YAMLError as e:
            fallos.append(f"{wf.name} no es YAML válido: {e}")
        for ruta in set(re.findall(r"scripts/[\w./-]+\.(?:sh|py)", texto)):
            if not (RAIZ / ruta).exists():
                fallos.append(f"{wf.name} usa '{ruta}', que no existe")


# ---------------------------------------------------------------------------
# Catálogo de recursos e icono
# ---------------------------------------------------------------------------
def comprobar_recursos(fallos: list[str]) -> None:
    for contents in RAIZ.glob("App/Resources/**/Contents.json"):
        try:
            json.loads(contents.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            fallos.append(f"{contents.relative_to(RAIZ)} no es JSON válido: {e}")

    icono = RAIZ / "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    if not icono.exists():
        fallos.append("Falta el icono AppIcon.png (ejecuta python scripts/generar_icono.py)")
        return
    try:
        from PIL import Image
    except ImportError:
        fallos.append("Falta Pillow para revisar el icono: python -m pip install pillow")
        return
    with Image.open(icono) as img:
        if img.size != (1024, 1024):
            fallos.append(f"El icono mide {img.size}, debe ser 1024x1024")
        if img.mode != "RGB":
            fallos.append(f"El icono está en modo {img.mode}; debe ser RGB sin alfa")


# ---------------------------------------------------------------------------
# Swift: balanceo de delimitadores ignorando cadenas y comentarios
# ---------------------------------------------------------------------------
class _Escaner:
    def __init__(self, texto: str):
        self.t = texto
        self.n = len(texto)
        self.i = 0
        self.linea = 1

    def _avanzar(self, k: int = 1) -> None:
        for _ in range(k):
            if self.i < self.n and self.t[self.i] == "\n":
                self.linea += 1
            self.i += 1

    def _saltar_comentario_bloque(self) -> str | None:
        # Swift permite comentarios de bloque anidados.
        inicio = self.linea
        profundidad = 0
        while self.i < self.n:
            if self.t.startswith("/*", self.i):
                profundidad += 1
                self._avanzar(2)
            elif self.t.startswith("*/", self.i):
                profundidad -= 1
                self._avanzar(2)
                if profundidad == 0:
                    return None
            else:
                self._avanzar()
        return f"comentario /* sin cerrar (línea {inicio})"

    def _cadena(self, multilinea: bool, almohadillas: int) -> str | None:
        inicio = self.linea
        cierre = ('"""' if multilinea else '"') + "#" * almohadillas
        escape = "\\" + "#" * almohadillas
        while self.i < self.n:
            c = self.t[self.i]
            if c == "\n" and not multilinea:
                return f"cadena sin cerrar (línea {inicio})"
            if self.t.startswith(escape, self.i):
                self._avanzar(len(escape))
                if self.i < self.n and self.t[self.i] == "(":
                    self._avanzar()
                    error = self.codigo(hasta_parentesis=True)
                    if error:
                        return error
                else:
                    self._avanzar()
                continue
            if self.t.startswith(cierre, self.i):
                self._avanzar(len(cierre))
                return None
            self._avanzar()
        return f"cadena sin cerrar (línea {inicio})"

    def codigo(self, hasta_parentesis: bool = False) -> str | None:
        pila: list[tuple[str, int]] = []
        while self.i < self.n:
            t, i = self.t, self.i
            c = t[i]
            if t.startswith("//", i):
                while self.i < self.n and self.t[self.i] != "\n":
                    self._avanzar()
                continue
            if t.startswith("/*", i):
                error = self._saltar_comentario_bloque()
                if error:
                    return error
                continue
            if c == "#":
                j = i
                while j < self.n and t[j] == "#":
                    j += 1
                if j < self.n and t[j] == '"':
                    almohadillas = j - i
                    self._avanzar(almohadillas)
                    multilinea = t.startswith('"""', self.i)
                    self._avanzar(3 if multilinea else 1)
                    error = self._cadena(multilinea, almohadillas)
                    if error:
                        return error
                    continue
                self._avanzar()
                continue
            if c == '"':
                multilinea = t.startswith('"""', i)
                self._avanzar(3 if multilinea else 1)
                error = self._cadena(multilinea, 0)
                if error:
                    return error
                continue
            if c in "([{":
                pila.append((c, self.linea))
            elif c in ")]}":
                if not pila:
                    if hasta_parentesis and c == ")":
                        self._avanzar()
                        return None
                    return f"'{c}' sin pareja (línea {self.linea})"
                abierto, linea_abierto = pila.pop()
                if abierto != PARES[c]:
                    return (f"'{c}' en la línea {self.linea} cierra "
                            f"'{abierto}' de la línea {linea_abierto}")
            self._avanzar()
        if hasta_parentesis:
            return "interpolación \\( sin cerrar"
        if pila:
            abierto, linea_abierto = pila[-1]
            return f"'{abierto}' de la línea {linea_abierto} nunca se cierra"
        return None


def comprobar_swift(fallos: list[str]) -> int:
    total = 0
    for carpeta in CARPETAS_SWIFT:
        for archivo in sorted((RAIZ / carpeta).rglob("*.swift")):
            total += 1
            error = _Escaner(archivo.read_text(encoding="utf-8")).codigo()
            if error:
                fallos.append(f"{archivo.relative_to(RAIZ)}: {error}")
    return total


# ---------------------------------------------------------------------------
# Scripts de shell
# ---------------------------------------------------------------------------
def comprobar_scripts(fallos: list[str]) -> None:
    for script in RAIZ.glob("scripts/**/*.sh"):
        datos = script.read_bytes()
        if b"\r\n" in datos:
            fallos.append(f"{script.relative_to(RAIZ)} tiene finales de línea CRLF (deben ser LF)")
        if not datos.startswith(b"#!"):
            fallos.append(f"{script.relative_to(RAIZ)} no empieza con #!")


def main() -> int:
    # La consola de Windows no siempre usa UTF-8; evita errores al imprimir tildes.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    fallos: list[str] = []
    comprobar_yaml(fallos)
    comprobar_recursos(fallos)
    n_swift = comprobar_swift(fallos)
    comprobar_scripts(fallos)
    if fallos:
        print("FALLOS:")
        for f in fallos:
            print(f"  - {f}")
        return 1
    print(f"OK ({n_swift} archivos Swift revisados)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
