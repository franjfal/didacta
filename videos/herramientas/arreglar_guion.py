"""Pone en bloque (`>-`) los textos de un guion que YAML no lee sueltos.

    python3 videos/herramientas/arreglar_guion.py videos/B01-…/guion.yaml

Un `texto: …` con «: » en medio es, para YAML, una clave dentro de otra, y
el guion no se lee. Esto lo reescribe como bloque, sin tocar lo demás, y
comprueba que después se lee. De paso entrecomilla los iconos que YAML
tomaría por un sí o un no (`icono: no` es `false`).
"""

import re
import sys

import yaml


def arreglar(ruta: str) -> int:
    lineas = open(ruta, encoding="utf-8").read().split("\n")
    salida, cambios = [], 0
    for linea in lineas:
        linea, n = re.subn(r"\b(icono|marca): (no|yes|on|off|si)\b(?!\")", r'\1: "\2"', linea)
        cambios += n
        m = re.match(r"^(\s*)(- )?(texto|lema_texto): (?![>|'\"])(.*: .*)$", linea)
        if m:
            sangria = m.group(1) + ("  " if m.group(2) else "")
            salida.append(f"{m.group(1)}{m.group(2) or ''}{m.group(3)}: >-")
            salida.append(f"{sangria}  {m.group(4)}")
            cambios += 1
        else:
            salida.append(linea)
    open(ruta, "w", encoding="utf-8").write("\n".join(salida))
    yaml.safe_load(open(ruta, encoding="utf-8"))
    return cambios


if __name__ == "__main__":
    for ruta in sys.argv[1:]:
        print(f"{ruta}: {arreglar(ruta)} arreglada(s)")
