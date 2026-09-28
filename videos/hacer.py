#!/usr/bin/env python3
"""Hacer un videotutorial de Didacta, de principio a fin.

    python3 videos/hacer.py preparar          # una vez: el entorno de voz y el de imagen
    python3 videos/hacer.py voz narrador      # una vez: el casting de la voz
    python3 videos/hacer.py A01               # el vídeo A01, entero
    python3 videos/hacer.py A01 --fotos 5,30  # solo unos fotogramas, para mirar
    python3 videos/hacer.py todos             # todos los vídeos

Un vídeo es una carpeta ``videos/A01-…`` con tres ficheros:

* ``guion.yaml`` -- lo que se dice, escena a escena, y los PDF que salen;
* ``capturas.json`` -- qué pantallas de la aplicación se fotografían y qué
  zonas de cada una interesan;
* ``escenas.js`` -- el montaje: qué se ve mientras se dice cada frase.

Y lo que sale va a ``videos/salida/``: el MP4 con sus subtítulos dentro, los
subtítulos sueltos (.vtt y .srt), los capítulos y una imagen de portada.

**Rehacer un vídeo cuando cambia la aplicación es volver a ejecutar esto.**
Las capturas se vuelven a sacar de la aplicación de ahora, los PDF se vuelven
a compilar con el motor de ahora, y el montaje se engancha a las zonas por su
nombre y a la voz por sus palabras, así que nada se queda apuntando a donde
estaba antes. Cada paso se salta si nada de lo suyo ha cambiado: la voz ya
dicha, por ejemplo, no se vuelve a decir.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

VIDEOS = Path(__file__).resolve().parent
RAIZ = VIDEOS.parent
VENV = VIDEOS / ".venv"
PY = VENV / "bin" / "python"
BUILD = VIDEOS / ".build"
SALIDA = VIDEOS / "salida"


def dentro_del_entorno() -> None:
    """Todo menos `preparar` corre con el Python del entorno de voz."""
    if Path(sys.prefix).resolve() == VENV.resolve():
        return
    if not PY.exists():
        raise SystemExit("Falta el entorno. Una vez:\n  python3 videos/hacer.py preparar")
    os.execv(str(PY), [str(PY), str(Path(__file__).resolve()), *sys.argv[1:]])


def paso(texto: str) -> None:
    print(f"\n\033[1;32m▸\033[0m \033[1m{texto}\033[0m", flush=True)


def correr(orden: list[str], **kw) -> None:
    resultado = subprocess.run(orden, **kw)
    if resultado.returncode != 0:
        raise SystemExit(f"Falló: {' '.join(map(str, orden))}")


# ------------------------------------------------------------- preparar ---


def preparar() -> None:
    """El entorno de voz (Python) y el de imagen (Node), una sola vez."""
    python = None
    for nombre in ("python3.12", "python3.11", "python3.10"):
        encontrado = shutil.which(nombre)
        if encontrado:
            python = encontrado
            break
    if not python:
        raise SystemExit("Hace falta Python 3.10 o posterior (por ejemplo: brew install python@3.11).")
    paso(f"Entorno de voz, con {python}")
    if not PY.exists():
        correr([python, "-m", "venv", str(VENV)])
    correr([str(PY), "-m", "pip", "install", "--no-cache-dir", "-q", "--upgrade", "pip"])
    correr([str(PY), "-m", "pip", "install", "--no-cache-dir", "-r", str(VIDEOS / "requirements.txt")])
    paso("Entorno de imagen (Node)")
    correr(["npm", "install", "--no-fund", "--no-audit"], cwd=VIDEOS)
    for herramienta in ("ffmpeg", "gs", "flutter"):
        if not shutil.which(herramienta) and not (herramienta == "flutter" and flutter()):
            print(f"  ¡ojo! falta {herramienta}")
    print("\nListo. Los modelos de voz se descargan la primera vez que se usan (~9 GB).")


def flutter() -> str | None:
    for candidato in (os.environ.get("FLUTTER"), shutil.which("flutter"), str(Path.home() / "flutter-sdk/bin/flutter")):
        if candidato and Path(candidato).exists():
            return candidato
    return None


# --------------------------------------------------------------- vídeos ---


def carpeta_de(codigo: str) -> Path:
    encontradas = sorted(p for p in VIDEOS.iterdir() if p.is_dir() and p.name.upper().startswith(codigo.upper()))
    if not encontradas:
        raise SystemExit(f"No hay ningún vídeo que empiece por «{codigo}» en {VIDEOS}")
    return encontradas[0]


def ultimo_cambio(*rutas: Path) -> float:
    """El fichero más reciente de unas carpetas: si es posterior a lo hecho, se rehace."""
    ultimo = 0.0
    for ruta in rutas:
        if ruta.is_file():
            ultimo = max(ultimo, ruta.stat().st_mtime)
        elif ruta.is_dir():
            for f in ruta.rglob("*"):
                if f.is_file() and ".didacta-build" not in f.parts and "build" not in f.parts[len(ruta.parts):len(ruta.parts) + 1]:
                    ultimo = max(ultimo, f.stat().st_mtime)
    return ultimo


def al_dia(sello: Path, *fuentes: Path) -> bool:
    return sello.exists() and sello.stat().st_mtime >= ultimo_cambio(*fuentes)


def capturas(carpeta: Path, obra: Path, forzar: bool) -> dict:
    destino = obra / "capturas"
    sello = destino / ".hecho"
    spec = json.loads((carpeta / "capturas.json").read_text(encoding="utf-8"))
    fuentes = (carpeta / "capturas.json", RAIZ / "app" / "lib", RAIZ / "app" / "assets" / "ejemplo", RAIZ / "app" / "tool" / "shots_video.dart")
    if not spec.get("capturas"):
        destino.mkdir(parents=True, exist_ok=True)
        sello.touch()
    if forzar or not al_dia(sello, *fuentes):
        paso("Capturas de la aplicación (con el repositorio de ejemplo)")
        exe = flutter()
        if not exe:
            raise SystemExit("Hace falta Flutter para sacar las capturas.")
        if destino.exists():
            shutil.rmtree(destino)
        correr(
            [exe, "test", "tool/shots_video.dart", "--reporter", "compact"],
            cwd=RAIZ / "app",
            env={**os.environ, "DIDACTA_VIDEO": carpeta.name, **motor_neutro()},
        )
        sello.touch()
    else:
        paso("Capturas: al día")
    if spec.get("web"):
        capturas_web(carpeta, destino, forzar)
    resultado = {}
    for zonas in sorted(destino.glob("*.json")):
        datos = json.loads(zonas.read_text(encoding="utf-8"))
        resultado[zonas.stem] = {
            "src": zonas.with_suffix(".png").resolve().as_uri(),
            "ancho": datos["ancho"],
            "alto": datos["alto"],
            "zonas": datos["zonas"],
            "direccion": datos.get("direccion", ""),
        }
    return resultado


def motor_neutro() -> dict:
    """Dónde enseña la aplicación que está el motor, en las capturas.

    El de verdad es este clon, y su ruta lleva el nombre de quien graba. Un
    enlace en `/Users/Shared/Didacta/motor` (en macOS) se lee como el de una
    instalación cualquiera. Si no se puede crear, se enseña la de verdad. La
    copia del repositorio de ejemplo va al lado, en
    `/Users/Shared/Didacta/didacta-ejemplo`, por lo mismo.
    """
    enlace = Path("/Users/Shared/Didacta/motor")
    try:
        if not enlace.exists():
            enlace.parent.mkdir(parents=True, exist_ok=True)
            enlace.symlink_to(RAIZ)
        return {"DIDACTA_MOTOR_VIDEO": str(enlace), "DIDACTA_RAIZ_VIDEO": str(enlace.parent)}
    except OSError:
        return {}


def capturas_web(carpeta: Path, destino: Path, forzar: bool) -> None:
    """Las páginas de la web de documentación que salen en el vídeo.

    Se construye la web de ahora --con el bloque de descargas de la última
    versión publicada, que es el que ve quien la visita-- y
    `estudio/web.mjs` la fotografía con sus zonas. El bloque de descargas del
    repositorio no se queda cambiado: se escribe para construir y se deja
    como estaba.
    """
    sello = destino / ".hecho-web"
    web = RAIZ / "web"
    fuentes = (carpeta / "capturas.json", web / "docs", web / "mkdocs.yml", web / "overrides", web / "hooks", RAIZ / "packaging" / "web.py")
    if not forzar and al_dia(sello, *fuentes):
        paso("Capturas de la web: al día")
        return
    paso("Capturas de la web de documentación")
    sitio = BUILD / "web"
    trozo = web / "docs" / "_snippets" / "descargas.md"
    antes = trozo.read_bytes()
    try:
        correr([sys.executable, str(RAIZ / "packaging" / "web.py"), "downloads", "--repo", "franjfal/didacta", "--out", str(trozo)])
        correr([str(VENV / "bin" / "mkdocs"), "build", "--quiet", "-d", str(sitio)], cwd=web)
    finally:
        trozo.write_bytes(antes)
    correr(["node", str(VIDEOS / "estudio" / "web.mjs"), str(sitio), str(carpeta / "capturas.json"), str(destino)])
    sello.touch()


def pdfs(guion: dict, carpeta: Path, obra: Path, forzar: bool) -> dict:
    sys.path.insert(0, str(VIDEOS / "herramientas"))
    import pdf

    destino = obra / "pdf"
    sello = destino / "pdf.json"
    fuentes = (carpeta / "guion.yaml", RAIZ / "latex", RAIZ / "engine", RAIZ / "app" / "assets" / "ejemplo")
    if not guion.get("pdf"):
        return {}
    if forzar or not al_dia(sello, *fuentes):
        paso("PDF, compilados con el motor")
        destino.mkdir(parents=True, exist_ok=True)
        return pdf.hacer(guion["pdf"], destino)
    paso("PDF: al día")
    return json.loads(sello.read_text(encoding="utf-8"))


def voz(guion: dict) -> dict:
    sys.path.insert(0, str(VIDEOS / "herramientas"))
    import voz as modulo

    paso(f"Voz ({guion.get('voz', 'narrador')})")
    frases = [{"id": f["id"], "texto": " ".join(f["texto"].split())} for e in guion["escenas"] for f in e["frases"]]
    hechas = modulo.locutar(frases, guion.get("voz", "narrador"))
    # El acento, en el vídeo entero: clonar puede irse al seseo sin avisar.
    import acento

    d = acento.distincion_de_varias([(Path(r["wav"]), r.get("palabras", [])) for r in hechas])
    aviso = "" if d["db"] is None or d["db"] >= 6 else "  ← ¡suena a seseo! revisar la voz"
    print(f"  acento: distinción z/s {d['db']} dB ({d['z']} palabras con z, {d['s']} con s){aviso}")
    return {r["id"]: r for r in hechas}


def tiempos(guion: dict, dichas: dict) -> dict:
    """Dónde cae cada escena y cada frase. Nada de esto se escribe a mano."""
    t = 0.0
    escenas = []
    numero = 0
    for e in guion["escenas"]:
        ini = t
        t += float(e.get("antes", 0.4))
        frases = []
        for i, f in enumerate(e["frases"]):
            d = dichas[f["id"]]
            f_ini = t
            f_fin = t + d["duracion"]
            frases.append({
                "id": f["id"],
                "texto": " ".join(f["texto"].split()),
                "ini": round(f_ini, 3),
                "fin": round(f_fin, 3),
                "wav": d["wav"],
                "palabras": [{"p": w["p"], "ini": round(f_ini + w["ini"], 3), "fin": round(f_ini + w["fin"], 3)} for w in d.get("palabras", [])],
            })
            ultima = i == len(e["frases"]) - 1
            t = f_fin + (0 if ultima else float(f.get("pausa", 0.32)))
        t += float(e.get("despues", 0.55))
        if e.get("capitulo"):
            numero += 1
        escenas.append({"id": e["id"], "capitulo": e.get("capitulo", ""), "numero": numero if e.get("capitulo") else 0, "ini": round(ini, 3), "fin": round(t, 3), "frases": frases})
    return {"total": round(t, 3), "escenas": escenas}


def pagina(carpeta: Path, obra: Path, datos: dict) -> Path:
    (obra / "datos.js").write_text("window.DATOS = " + json.dumps(datos, ensure_ascii=False) + ";\n", encoding="utf-8")
    # El montaje: el del vídeo si tiene uno; si no, el que sale de su guion.
    if (carpeta / "escenas.js").exists():
        propio = f'<script src="{(carpeta / "escenas.js").as_uri()}"></script>'
    else:
        propio = "<script>window.montaje = (E, G, D) => Recorrido.montar(E, G, D);</script>"
    html = f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<link rel="stylesheet" href="{(VIDEOS / 'estudio' / 'estudio.css').as_uri()}">
</head><body><div id="lienzo"></div>
<script src="{(obra / 'datos.js').as_uri()}"></script>
<script src="{(VIDEOS / 'estudio' / 'estudio.js').as_uri()}"></script>
<script src="{(VIDEOS / 'estudio' / 'recorrido.js').as_uri()}"></script>
{propio}
<script>Estudio.arrancar();</script>
</body></html>
"""
    destino = obra / "pagina.html"
    destino.write_text(html, encoding="utf-8")
    return destino


# ----------------------------------------------------------------- audio ---


def sonido_sintetico(tipo: str, sr: int):
    """Los dos únicos efectos: un clic de ratón y un soplo de transición.

    Se sintetizan en lugar de descargarse, para que no haya ningún fichero de
    audio de terceros en el camino.
    """
    import numpy as np

    rng = np.random.default_rng(7)
    if tipo == "clic":
        n = int(0.05 * sr)
        t = np.arange(n) / sr
        ruido = rng.standard_normal(n) * np.exp(-t / 0.004)
        from scipy.signal import butter, lfilter

        b, a = butter(2, [1800 / (sr / 2), 7000 / (sr / 2)], btype="band")
        golpe = lfilter(b, a, ruido) * 0.5 + np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.012) * 0.35
        return golpe * 0.25
    if tipo == "soplo":
        n = int(0.55 * sr)
        t = np.arange(n) / sr
        from scipy.signal import butter, lfilter

        ruido = rng.standard_normal(n)
        b, a = butter(2, [300 / (sr / 2), 2400 / (sr / 2)], btype="band")
        envolvente = np.sin(np.pi * t / t[-1]) ** 2
        return lfilter(b, a, ruido) * envolvente * 0.035
    return np.zeros(1)


def mezclar(datos_tiempos: dict, sonidos: list, destino: Path) -> None:
    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly

    sr = 48000
    total = int((datos_tiempos["total"] + 0.5) * sr)
    pista = np.zeros(total, dtype=np.float64)
    for e in datos_tiempos["escenas"]:
        for f in e["frases"]:
            onda, sr_voz = sf.read(f["wav"], dtype="float64")
            if sr_voz != sr:
                from math import gcd

                g = gcd(sr, sr_voz)
                onda = resample_poly(onda, sr // g, sr_voz // g)
            a = int(f["ini"] * sr)
            b = min(total, a + len(onda))
            pista[a:b] += onda[: b - a]
    for s in sonidos:
        efecto = sonido_sintetico(s["tipo"], sr) * float(s.get("volumen", 1))
        a = int(s["t"] * sr)
        b = min(total, a + len(efecto))
        pista[a:b] += efecto[: b - a]
    sf.write(destino, pista.astype(np.float32), sr, subtype="FLOAT")


# ----------------------------------------------------------- subtítulos ---


def trozos(texto: str, maximo: int = 84) -> list[str]:
    """Parte una frase en subtítulos de dos líneas como mucho, por la puntuación."""
    if len(texto) <= maximo:
        return [texto]
    partes = re.split(r"(?<=[,:;.…])\s+", texto)
    salida, actual = [], ""
    for p in partes:
        if actual and len(actual) + 1 + len(p) > maximo:
            salida.append(actual)
            actual = p
        else:
            actual = f"{actual} {p}".strip()
    if actual:
        salida.append(actual)
    final = []
    for s in salida:
        while len(s) > maximo:
            corte = s.rfind(" ", 0, maximo)
            final.append(s[:corte])
            s = s[corte + 1 :]
        final.append(s)
    return final


def dos_lineas(texto: str, ancho: int = 42) -> str:
    if len(texto) <= ancho:
        return texto
    medio = len(texto) // 2
    izquierda = texto.rfind(" ", 0, medio + 1)
    derecha = texto.find(" ", medio)
    corte = izquierda if derecha < 0 or (izquierda >= 0 and medio - izquierda <= derecha - medio) else derecha
    return texto[:corte] + "\n" + texto[corte + 1 :]


def subtitulos(datos_tiempos: dict) -> list[tuple[float, float, str]]:
    sys.path.insert(0, str(VIDEOS / "herramientas"))
    from voz import normalizar

    cues = []
    for e in datos_tiempos["escenas"]:
        for f in e["frases"]:
            partes = trozos(f["texto"])
            total_palabras = max(1, len(normalizar(f["texto"])))
            oidas = f["palabras"]
            hechas = 0
            for i, parte in enumerate(partes):
                n = len(normalizar(parte))
                if oidas:
                    k0 = min(len(oidas) - 1, round(hechas / total_palabras * len(oidas)))
                    k1 = min(len(oidas) - 1, round((hechas + n) / total_palabras * len(oidas)) - 1)
                    ini = f["ini"] if i == 0 else oidas[k0]["ini"]
                    fin = f["fin"] if i == len(partes) - 1 else oidas[max(k0, k1)]["fin"]
                else:
                    ini = f["ini"] + (f["fin"] - f["ini"]) * hechas / total_palabras
                    fin = f["ini"] + (f["fin"] - f["ini"]) * (hechas + n) / total_palabras
                cues.append((ini, max(fin, ini + 1.0), dos_lineas(parte)))
                hechas += n
    # Que ninguno pise al siguiente.
    arreglados = []
    for i, (a, b, texto) in enumerate(cues):
        if i + 1 < len(cues):
            b = min(b + 0.25, cues[i + 1][0] - 0.04)
        arreglados.append((a, b, texto))
    return arreglados


def marca_tiempo(t: float, coma: bool) -> str:
    h, resto = divmod(t, 3600)
    m, s = divmod(resto, 60)
    return f"{int(h):02d}:{int(m):02d}:{s:06.3f}".replace(".", "," if coma else ".")


def escribir_subtitulos(cues, base: Path) -> tuple[Path, Path]:
    srt = base.with_suffix(".es.srt")
    vtt = base.with_suffix(".es.vtt")
    srt.write_text("\n".join(f"{i}\n{marca_tiempo(a, True)} --> {marca_tiempo(b, True)}\n{t}\n" for i, (a, b, t) in enumerate(cues, 1)), encoding="utf-8")
    vtt.write_text("WEBVTT\n\n" + "\n".join(f"{marca_tiempo(a, False)} --> {marca_tiempo(b, False)}\n{t}\n" for a, b, t in cues), encoding="utf-8")
    return srt, vtt


# ---------------------------------------------------------------- montar ---


def hacer(codigo: str, opciones: dict) -> None:
    import yaml

    carpeta = carpeta_de(codigo)
    guion = yaml.safe_load((carpeta / "guion.yaml").read_text(encoding="utf-8"))
    obra = BUILD / carpeta.name
    obra.mkdir(parents=True, exist_ok=True)
    print(f"\033[1m{guion['codigo']} · {guion['titulo']}\033[0m  ({carpeta.relative_to(RAIZ)})")

    version = re.search(r"^version:\s*([\d.]+)", (RAIZ / "app" / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    datos = {
        "video": {
            **{k: guion.get(k, "") for k in ("codigo", "titulo", "subtitulo", "ruta", "siguiente")},
            # La versión de la aplicación que se enseña: sale en los nombres
            # de los instaladores, por ejemplo.
            "version": version.group(1) if version else "",
        },
        # El guion entero: el montaje genérico (`estudio/recorrido.js`) lee
        # de él lo que se ve en cada frase.
        "guion": guion,
        "capturas": capturas(carpeta, obra, "capturas" in opciones["rehacer"]),
        "pdf": pdfs(guion, carpeta, obra, "pdf" in opciones["rehacer"]),
    }
    dichas = voz(guion)
    datos["tiempos"] = tiempos(guion, dichas)
    html = pagina(carpeta, obra, datos)
    print(f"  {datos['tiempos']['total']:.1f} s, {sum(len(e['frases']) for e in datos['tiempos']['escenas'])} frases")

    grabar = VIDEOS / "estudio" / "grabar.mjs"
    if opciones["fotos"]:
        paso("Fotogramas sueltos")
        correr(["node", str(grabar), str(html), str(obra / "fotos"), "--fotos", opciones["fotos"]])
        return

    mudo = obra / "imagen.mp4"
    # La imagen solo se vuelve a pintar si ha cambiado algo de lo que la hace.
    import hashlib

    h = hashlib.sha1()
    for f in (obra / "datos.js", carpeta / "escenas.js", *sorted((VIDEOS / "estudio").glob("*"))):
        if f.is_file():
            h.update(f.read_bytes())
    # Y las capturas: `datos.js` las nombra, pero una captura nueva con las
    # mismas zonas --a otra resolución, por ejemplo-- no lo cambia.
    for f in sorted((obra / "capturas").glob("*.png")):
        h.update(f"{f.name} {f.stat().st_size} {f.stat().st_mtime_ns}".encode())
    h.update(str(opciones["fps"]).encode())
    huella = obra / "imagen.huella"
    if mudo.exists() and huella.exists() and huella.read_text() == h.hexdigest() and "imagen" not in opciones["rehacer"]:
        paso("Imagen: al día")
    else:
        paso("Imagen, fotograma a fotograma")
        correr(["node", str(grabar), str(html), str(mudo), "--fps", str(opciones["fps"])])
        huella.write_text(h.hexdigest())
    sonidos = json.loads(mudo.with_suffix(".sonidos.json").read_text(encoding="utf-8"))

    paso("Sonido y subtítulos")
    narracion = obra / "sonido.wav"
    mezclar(datos["tiempos"], sonidos, narracion)
    SALIDA.mkdir(exist_ok=True)
    base = SALIDA / carpeta.name
    srt, vtt = escribir_subtitulos(subtitulos(datos["tiempos"]), base)

    # Los capítulos: para la descripción del vídeo y dentro del propio MP4.
    capitulos = [e for e in datos["tiempos"]["escenas"] if e["capitulo"] or e["id"] == "apertura"]
    lineas = []
    meta = [";FFMETADATA1", f"title=Didacta · {guion['codigo']} · {guion['titulo']}"]
    for i, e in enumerate(capitulos):
        nombre = e["capitulo"] or guion["titulo"]
        m, s = divmod(int(e["ini"]), 60)
        lineas.append(f"{m}:{s:02d} {nombre}")
        fin = capitulos[i + 1]["ini"] if i + 1 < len(capitulos) else datos["tiempos"]["total"]
        meta += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={int(e['ini'] * 1000)}", f"END={int(fin * 1000)}", f"title={nombre}"]
    base.with_suffix(".capitulos.txt").write_text("\n".join(lineas) + "\n", encoding="utf-8")
    ffmeta = obra / "capitulos.ffmeta"
    ffmeta.write_text("\n".join(meta) + "\n", encoding="utf-8")

    # Volumen de emisión (-16 LUFS), en dos pasadas: medir y luego aplicar.
    medida = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(narracion), "-af", "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
        capture_output=True, text=True,
    ).stderr
    m = json.loads(medida[medida.rindex("{") : medida.rindex("}") + 1])
    filtro = (
        f"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
        f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true"
    )
    final = base.with_suffix(".mp4")
    correr([
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(mudo), "-i", str(narracion), "-i", str(srt), "-i", str(ffmeta),
        "-map", "0:v", "-map", "1:a", "-map", "2:s", "-map_metadata", "3", "-map_chapters", "3",
        "-c:v", "copy", "-af", filtro, "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
        "-c:s", "mov_text", "-metadata:s:a:0", "language=spa", "-metadata:s:s:0", "language=spa",
        # La duración, dicha: con `-shortest` mandaba el último subtítulo y se
        # comía la espera del final.
        "-t", f"{datos['tiempos']['total']:.3f}", "-movflags", "+faststart", str(final),
    ])
    t_portada = momento_de_portada(guion, datos["tiempos"])
    correr(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t_portada:.2f}", "-i", str(mudo), "-frames:v", "1", "-q:v", "2", str(base.with_suffix(".jpg"))])
    print(f"\n\033[1;32m✓\033[0m {final.relative_to(RAIZ)}  ({datos['tiempos']['total']:.0f} s)")
    for extra in (vtt, srt, base.with_suffix(".capitulos.txt"), base.with_suffix(".jpg")):
        print(f"  {extra.relative_to(RAIZ)}")
    publicar_en_la_web(carpeta, guion, datos["tiempos"], final, mudo, t_portada, vtt)


def momento_de_portada(guion: dict, t: dict) -> float:
    """El fotograma de la miniatura: el título ya entero, salvo que el guion
    diga otro (`miniatura: 12.5`, en segundos, o el id de una frase)."""
    pedida = guion.get("miniatura")
    if isinstance(pedida, (int, float)):
        return float(pedida)
    for e in t["escenas"]:
        for f in e["frases"]:
            if f["id"] == pedida:
                return f["fin"] - 0.2
    apertura = next((e for e in t["escenas"] if e["id"] == "apertura"), None)
    return (apertura["fin"] - 0.6) if apertura else 3.0


# ------------------------------------------------------------------ web ---

WEB = RAIZ / "web" / "docs" / "videos"


def publicar_en_la_web(carpeta: Path, guion: dict, t: dict, final: Path, mudo: Path, t_portada: float, vtt: Path) -> None:
    """Lo que la web necesita de un vídeo terminado.

    En `web/docs/videos/a1/`, la miniatura, la portada, los subtítulos, los
    capítulos y la transcripción: pesan poco, los encuentra el buscador y
    cambian cuando cambia el vídeo. En `web/docs/videos/media/`, el MP4, más
    ligero que el de `salida/` y sin la pista de subtítulos. Todo va al
    repositorio con la documentación, y la web lo publica tal cual (ver
    «Los vídeos» en `web/README.md`).
    """
    import datetime

    paso("La web")
    codigo = guion["codigo"]
    destino = WEB / codigo.lower()
    destino.mkdir(parents=True, exist_ok=True)

    # El vídeo para la web: el mismo, con la compresión que se nota en el
    # peso y no en la pantalla (~4 MB por minuto; el texto de un PDF se sigue
    # leyendo). Sin pista de subtítulos dentro: en la web van aparte.
    ligero = WEB / "media" / final.name
    ligero.parent.mkdir(parents=True, exist_ok=True)
    correr([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(final), "-map", "0:v", "-map", "0:a",
        "-c:v", "libx264", "-preset", "slow", "-crf", "25", "-tune", "animation", "-pix_fmt", "yuv420p",
        "-profile:v", "high", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(ligero),
    ])
    for nombre, ancho in (("portada.jpg", 1280), ("miniatura.jpg", 640)):
        correr([
            "ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t_portada:.2f}", "-i", str(mudo), "-frames:v", "1",
            "-vf", f"scale={ancho}:-2:flags=lanczos", "-q:v", "3", str(destino / nombre),
        ])
    shutil.copyfile(vtt, destino / "es.vtt")

    capitulos = []
    transcripcion = []
    for e in t["escenas"]:
        nombre = e["capitulo"] or (guion["titulo"] if e["id"] == "apertura" else "")
        if nombre:
            capitulos.append({"t": round(e["ini"], 2), "titulo": nombre})
        for f in e["frases"]:
            transcripcion.append({"t": round(f["ini"], 2), "texto": f["texto"]})
    fin = t["total"]
    (destino / "capitulos.vtt").write_text(
        "WEBVTT\n\n" + "\n".join(
            f"{marca_tiempo(c['t'], False)} --> {marca_tiempo(capitulos[i + 1]['t'] if i + 1 < len(capitulos) else fin, False)}\n{c['titulo']}\n"
            for i, c in enumerate(capitulos)
        ),
        encoding="utf-8",
    )
    version = re.search(r"^version:\s*([\d.]+)", (RAIZ / "app" / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    ficha = {
        "codigo": codigo,
        "titulo": guion["titulo"],
        "fichero": final.name,
        "duracion": round(fin, 2),
        "megas": round(ligero.stat().st_size / 1e6, 1),
        "fecha": datetime.date.today().isoformat(),
        "version": version.group(1) if version else "",
        "capitulos": capitulos,
        "transcripcion": transcripcion,
    }
    (destino / "video.json").write_text(json.dumps(ficha, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  {destino.relative_to(RAIZ)}/  (miniatura, subtítulos, capítulos, transcripción)")
    print(f"  {ligero.relative_to(RAIZ)}  ({ficha['megas']} MB)")


def main() -> None:
    argumentos = sys.argv[1:]
    if not argumentos or argumentos[0] in ("-h", "--help", "ayuda"):
        print(__doc__)
        return
    if argumentos[0] == "preparar":
        preparar()
        return
    dentro_del_entorno()
    if argumentos[0] == "voz":
        sys.path.insert(0, str(VIDEOS / "herramientas"))
        import casting

        casting.casting(argumentos[1] if len(argumentos) > 1 else "narrador")
        return
    opciones = {"fotos": None, "fps": 30, "rehacer": set()}
    codigos = []
    i = 0
    while i < len(argumentos):
        a = argumentos[i]
        if a == "--fotos":
            opciones["fotos"] = argumentos[i + 1]
            i += 1
        elif a == "--fps":
            opciones["fps"] = int(argumentos[i + 1])
            i += 1
        elif a == "--rehacer":
            opciones["rehacer"] = set(argumentos[i + 1].split(","))
            i += 1
        else:
            codigos.append(a)
        i += 1
    if codigos == ["todos"]:
        codigos = sorted(p.name[:3] for p in VIDEOS.iterdir() if p.is_dir() and (p / "guion.yaml").exists())
    for codigo in codigos:
        hacer(codigo, opciones)


if __name__ == "__main__":
    main()
