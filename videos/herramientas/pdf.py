"""Los PDF de un vídeo: compilados de verdad, y con sus zonas localizadas.

Un vídeo que enseña «así salen las diapositivas» tiene que enseñar las
diapositivas que salen hoy, no una captura de hace un año. Esto compila el
repositorio de ejemplo con el motor de Didacta --el mismo camino que el botón
de compilar--, busca la página **por su texto** y rasteriza.

Las zonas también se buscan por texto: «la nota didáctica» es desde las
palabras «Nota didáctica» hasta «la pizarra.», estén donde estén. Si mañana la
plantilla cambia los márgenes, el recuadro del vídeo se va con ellas.

Solo necesita ``gs`` (Ghostscript), que es lo que ya hay en cualquier máquina
con una distribución de TeX.
"""

from __future__ import annotations

import html
import json
import re
import shutil
import subprocess
import unicodedata
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
EJEMPLO = RAIZ / "app" / "assets" / "ejemplo"
MOTOR = RAIZ / "cli" / "didacta"


def normalizar(texto: str) -> list[str]:
    texto = unicodedata.normalize("NFKD", texto.lower())
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    # Las comillas y los apóstrofos tipográficos, como los de teclado.
    texto = texto.replace("’", "'").replace("‘", "'")
    return [t for t in re.split(r"\s+", texto) if t]


def preparar_ejemplo(destino: Path) -> Path:
    """Una copia limpia del repositorio de ejemplo, con su historial."""
    if destino.exists():
        shutil.rmtree(destino)
    shutil.copytree(EJEMPLO, destino)
    run = lambda *a: subprocess.run(a, cwd=destino, check=True, capture_output=True)  # noqa: E731
    run("git", "init", "-q", "--initial-branch=main")
    run("git", "add", "-A")
    run("git", "-c", "user.name=Didacta", "-c", "user.email=didacta@example.org", "commit", "-qm", "ejemplo")
    return destino


def compilar(repo: Path, documento: str, version: str, idioma: str) -> Path:
    """Compila una versión de un documento y devuelve su PDF."""
    salida = subprocess.run(
        [str(MOTOR), "build", documento, "-p", version, "-l", idioma],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    if salida.returncode != 0:
        raise SystemExit(f"No compila {documento} ({version}, {idioma}):\n{salida.stdout}{salida.stderr}")
    encontrados = sorted((repo / ".didacta-build").glob(f"*_{documento}/{version}-{idioma}/*.pdf"))
    if not encontrados:
        raise SystemExit(f"Compiló {documento} ({version}, {idioma}) pero no encuentro el PDF")
    return encontrados[0]


def palabras(pdf: Path) -> list[list[dict]]:
    """Las palabras de cada página, con su caja en puntos desde arriba."""
    salida = subprocess.run(
        ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=txtwrite", "-dTextFormat=0", "-o", "-", str(pdf)],
        capture_output=True,
        text=True,
        errors="replace",
    ).stdout
    paginas: list[list[dict]] = []
    for bloque in salida.split("<page>")[1:]:
        lista = []
        for span in re.finditer(r'<span bbox="([\d.\s-]+)" font="[^"]*" size="([\d.]+)">(.*?)</span>', bloque, re.S):
            x0, y0, x1, y1 = (float(v) for v in span.group(1).split())
            tam = float(span.group(2))
            texto = "".join(html.unescape(c) for c in re.findall(r'c="([^"]*)"', span.group(3)))
            if texto.strip():
                lista.append({"t": texto, "x0": x0, "x1": x1, "y": max(y0, y1), "tam": tam})
        paginas.append(lista)
    return paginas


def tamano(pdf: Path, pagina: int) -> tuple[float, float]:
    salida = subprocess.run(
        ["gs", "-q", "-dNODISPLAY", "-dNOSAFER", "-c",
         f"({pdf}) (r) file runpdfbegin {pagina} pdfgetpage /MediaBox pget pop == quit"],
        capture_output=True, text=True,
    ).stdout
    numeros = [float(v) for v in re.findall(r"[\d.]+", salida)]
    return numeros[2] - numeros[0], numeros[3] - numeros[1]


def _limpia(palabra: str) -> str:
    return re.sub(r"[^a-z0-9ñ]", "", "".join(normalizar(palabra)))


def buscar(lista: list[dict], texto: str, desde: int = 0) -> tuple[int, int] | None:
    """Dónde está un texto en la página: índices de su primera y última palabra.

    Se compara el texto **seguido**, sin espacios, tildes, mayúsculas ni
    puntuación: Ghostscript trocea las palabras por el interletraje
    («acerca» sale como «a» + «cerca»), y una búsqueda palabra a palabra se
    perdería. Los símbolos sueltos (ε, <) no cuentan.
    """
    objetivo = "".join(_limpia(w) for w in texto.split())
    if not objetivo:
        return None
    seguido = ""
    dueno: list[int] = []
    for k in range(desde, len(lista)):
        trozo = _limpia(lista[k]["t"])
        seguido += trozo
        dueno.extend([k] * len(trozo))
    at = seguido.find(objetivo)
    if at < 0:
        return None
    return dueno[at], dueno[at + len(objetivo) - 1]


def zona(lista: list[dict], desde: str, hasta: str | None, margen: float) -> list[float] | None:
    encontrado = buscar(lista, desde)
    if encontrado is None:
        return None
    i, j = encontrado
    if hasta:
        final = buscar(lista, hasta, i)
        if final is None:
            return None
        j = final[1]
        # Lo que va pegado detrás --un punto, un símbolo-- también es suyo.
        while j + 1 < len(lista) and not _limpia(lista[j + 1]["t"]) and abs(lista[j + 1]["y"] - lista[j]["y"]) < 2:
            j += 1
    tramo = lista[i : j + 1]
    x0 = min(p["x0"] for p in tramo) - margen
    x1 = max(p["x1"] for p in tramo) + margen
    y0 = min(p["y"] - p["tam"] * 0.82 for p in tramo) - margen
    y1 = max(p["y"] + p["tam"] * 0.24 for p in tramo) + margen
    return [x0, y0, x1 - x0, y1 - y0]


def rasterizar(pdf: Path, pagina: int, ppp: int, png: Path) -> None:
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=png16m", f"-r{ppp}",
         "-dTextAlphaBits=4", "-dGraphicsAlphaBits=4",
         f"-dFirstPage={pagina}", f"-dLastPage={pagina}", f"-sOutputFile={png}", str(pdf)],
        check=True,
    )


def hacer(pedidos: list[dict], carpeta: Path) -> dict:
    """Compila, busca, rasteriza y mide cada PDF que pide un guion."""
    repo = preparar_ejemplo(carpeta / "ejemplo")
    hechos: dict[tuple, Path] = {}
    resultado = {}
    for pedido in pedidos:
        clave = (pedido["documento"], pedido["version"], pedido["idioma"])
        if clave not in hechos:
            print(f"  compilando {clave[0]} · {clave[1]} · {clave[2]}", flush=True)
            hechos[clave] = compilar(repo, *clave)
        pdf = hechos[clave]
        paginas = palabras(pdf)
        numero = None
        for n, lista in enumerate(paginas, 1):
            if buscar(lista, pedido["pagina"]) is not None:
                numero = n
                break
        if numero is None:
            raise SystemExit(f"«{pedido['pagina']}» no está en ninguna página de {pdf.name}")
        ppp = int(pedido.get("ppp", 300))
        png = carpeta / f"{pedido['nombre']}.png"
        rasterizar(pdf, numero, ppp, png)
        ancho_pt, alto_pt = tamano(pdf, numero)
        escala = ppp / 72
        zonas = {}
        for nombre, que in (pedido.get("zonas") or {}).items():
            margen = float(que.get("margen", 10 if que.get("caja") else 3))
            z = zona(paginas[numero - 1], que["desde"], que.get("hasta"), margen)
            if z is None:
                print(f"    (sin zona «{nombre}» en {pedido['nombre']})")
                continue
            zonas[nombre] = [round(v * escala, 1) for v in z]
        resultado[pedido["nombre"]] = {
            "src": png.resolve().as_uri(),
            "ancho": round(ancho_pt * escala),
            "alto": round(alto_pt * escala),
            "pagina": numero,
            "zonas": zonas,
        }
        print(f"  {pedido['nombre']}: página {numero}, {len(zonas)} zona(s)", flush=True)
    (carpeta / "pdf.json").write_text(json.dumps(resultado, ensure_ascii=False, indent=1), encoding="utf-8")
    return resultado


if __name__ == "__main__":
    import sys

    # Para buscar a mano qué palabras hay en una página: pdf.py fichero.pdf 4
    for p in palabras(Path(sys.argv[1]))[int(sys.argv[2]) - 1]:
        print(f"{p['t']!r:28} x {p['x0']:6.1f}-{p['x1']:6.1f}  y {p['y']:6.1f}  {p['tam']:.1f}")
