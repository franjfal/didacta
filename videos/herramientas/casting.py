"""El casting de la voz: probar varias y quedarse con la que suena como debe.

    videos/.venv/bin/python videos/herramientas/casting.py narrador

Nadie tiene que escuchar treinta muestras. Cada candidata se genera con el
modelo de diseño de voz de Qwen3-TTS --una descripción, un muestreo y una
semilla-- y se mide:

* **fidelidad**: Whisper la transcribe y se compara con el texto;
* **acento**: si distingue la «z» de la «s» como en España
  (``acento.distincion``; con seseo sale cerca de cero);
* **altura y movimiento**: la mediana del tono, que para un barítono anda por
  los 100-130 Hz, y cuántos semitonos recorre --poco es plano, mucho es
  teatral--;
* **ritmo**: palabras por minuto;
* **naturalidad**: UTMOS, un modelo abierto entrenado para predecir la nota
  que pondrían oyentes de verdad.

Las que no pasan los mínimos se descartan, y de las demás gana la más
natural. Las tres mejores quedan en ``videos/voz/candidatas/`` para
escucharlas; la primera pasa a ser la voz (``narrador.wav``) y lo que la
produjo se apunta en el ``.yaml`` para poder repetirla.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
import yaml

sys.path.insert(0, str(Path(__file__).parent))
import acento  # noqa: E402
import voz  # noqa: E402

MUESTREOS = voz.MUESTREOS

SEMILLAS = [3, 17, 29]

# Los mínimos. Fuera de aquí, no vale aunque suene bonita.
MINIMOS = {
    "parecido": 0.93,  # dice lo que pone
    "distincion": 6.0,  # dB: distingue la «z» de la «s» (seseo, ~0)
    "hz": (88, 145),  # barítono
    "semitonos": (5.5, 11.5),  # ni plano ni teatral
    "ppm": (120, 170),  # palabras por minuto
}


class Naturalidad:
    """UTMOS: la nota de naturalidad, de 1 a 5."""

    def __init__(self) -> None:
        import torch

        self.torch = torch
        self.modelo = torch.hub.load("tarepan/SpeechMOS:v1.2.0", "utmos22_strong", trust_repo=True)

    def nota(self, wav: Path) -> float:
        import librosa

        onda, _ = librosa.load(str(wav), sr=16000)
        with self.torch.no_grad():
            return float(self.modelo(self.torch.from_numpy(onda).unsqueeze(0), 16000))


def pasa(c: dict) -> list[str]:
    fallos = []
    if c["parecido"] < MINIMOS["parecido"]:
        fallos.append("no dice el texto")
    if c["distincion"] is None or c["distincion"] < MINIMOS["distincion"]:
        fallos.append("sesea")
    lo, hi = MINIMOS["hz"]
    if c["hz"] is None or not lo <= c["hz"] <= hi:
        fallos.append("altura")
    lo, hi = MINIMOS["semitonos"]
    if c["semitonos"] is None or not lo <= c["semitonos"] <= hi:
        fallos.append("plana" if (c["semitonos"] or 0) < lo else "teatral")
    lo, hi = MINIMOS["ppm"]
    if not lo <= c["ppm"] <= hi:
        fallos.append("ritmo")
    return fallos


def puntuar(c: dict) -> float:
    # La naturalidad manda; el resto desempata hacia el centro de lo pedido.
    return (
        c["mos"]
        + 0.03 * min(c["distincion"] or 0, 14)
        - 0.04 * abs((c["semitonos"] or 8.5) - 8.5)
        - 0.004 * abs((c["hz"] or 115) - 115)
    )


def casting(nombre: str, semillas: list[int] | None = None, lenguas: list[str] | None = None,
            muestreos: list[str] | None = None) -> None:
    cfg = voz.leer_voz(nombre)
    carpeta = voz.CACHE / f"casting-{nombre}"
    carpeta.mkdir(parents=True, exist_ok=True)
    # Lo ya probado no se vuelve a generar: una ronda más suma candidatas.
    previas = carpeta / "casting.json"
    hechas = {c["clave"]: c for c in json.loads(previas.read_text(encoding="utf-8"))} if previas.exists() else {}
    modelo = None
    oido = voz.Oido()
    juez = Naturalidad()

    candidatas = list(hechas.values())
    for lengua, descripcion in cfg["descripciones"].items():
        if lenguas and lengua not in lenguas:
            continue
        for muestreo, ajustes in MUESTREOS.items():
            if muestreos and muestreo not in muestreos:
                continue
            for semilla in semillas or SEMILLAS:
                clave = f"{lengua}-{muestreo}-{semilla}"
                if clave in hechas:
                    continue
                if modelo is None:
                    modelo = voz.cargar(voz.DISENO)
                wav = carpeta / f"{clave}.wav"
                voz.sembrar(semilla)
                ondas, sr = modelo.generate_voice_design(
                    text=cfg["texto"], language=cfg["idioma"], instruct=descripcion, **ajustes
                )
                onda = voz.recortar(np.asarray(ondas[0], dtype=np.float32), sr)
                sf.write(wav, onda, sr)
                palabras = oido.palabras(wav)
                se_oye = " ".join(p["p"] for p in palabras)
                duracion = len(onda) / sr
                c = {
                    "clave": clave,
                    "lengua": lengua,
                    "muestreo": muestreo,
                    "semilla": semilla,
                    "wav": str(wav),
                    "parecido": round(voz.parecido(cfg["texto"], se_oye), 3),
                    "distincion": acento.distincion(wav, palabras)["db"],
                    **acento.tono(wav),
                    "ppm": round(len(voz.normalizar(se_oye)) / duracion * 60),
                    "mos": round(juez.nota(wav), 2),
                    "se_oye": se_oye,
                }
                c["fallos"] = pasa(c)
                c["puntos"] = round(puntuar(c), 3)
                candidatas.append(c)
                estado = "ok" if not c["fallos"] else ", ".join(c["fallos"])
                print(
                    f"  {clave:18} mos {c['mos']:.2f} · z/s {c['distincion']} dB · {c['hz']} Hz · "
                    f"{c['semitonos']} st · {c['ppm']} ppm · {c['parecido']:.2f}  [{estado}]",
                    flush=True,
                )

    (carpeta / "casting.json").write_text(json.dumps(candidatas, ensure_ascii=False, indent=1), encoding="utf-8")
    # Las que pasan todo, por puntos; detrás, para tener donde escoger, las
    # que solo fallan en una cosa que no sea el acento ni el texto.
    buenas = sorted((c for c in candidatas if not c["fallos"]), key=lambda c: -c["puntos"])
    casi = sorted(
        (c for c in candidatas if len(c["fallos"]) == 1 and c["fallos"][0] not in ("sesea", "no dice el texto")),
        key=lambda c: -c["puntos"],
    )
    if not buenas:
        print("Ninguna pasa todos los mínimos; me quedo con las de más puntos y lo digo.")
    buenas = buenas + casi
    if not buenas:
        buenas = sorted(candidatas, key=lambda c: (len(c["fallos"]), -c["puntos"]))

    destino = voz.VOCES / "candidatas"
    if destino.exists():
        shutil.rmtree(destino)
    destino.mkdir()
    for n, c in enumerate(buenas[:3], 1):
        shutil.copy(c["wav"], destino / f"{nombre}-{n}.wav")
    ganadora = buenas[0]
    shutil.copy(ganadora["wav"], cfg["muestra"])

    # Lo que la produjo, para poder repetirla: se reescribe solo el bloque
    # `elegida:` del final, sin tocar los comentarios de arriba.
    ruta = voz.VOCES / f"{nombre}.yaml"
    texto = ruta.read_text(encoding="utf-8")
    bloque = yaml.safe_dump(
        {"elegida": {
            "descripcion": ganadora["lengua"],
            "muestreo": ganadora["muestreo"],
            "semilla": ganadora["semilla"],
            "medidas": {k: ganadora[k] for k in ("mos", "distincion", "hz", "semitonos", "ppm", "parecido")},
        }},
        allow_unicode=True, sort_keys=False,
    )
    texto = texto[: texto.index("elegida:")] + bloque
    ruta.write_text(texto, encoding="utf-8")
    print(f"\nvoz «{nombre}»: {ganadora['clave']} → {cfg['muestra']}")
    for n, c in enumerate(buenas[:3], 1):
        extra = f"  [{', '.join(c['fallos'])}]" if c["fallos"] else ""
        print(f"  candidata {n}: {c['clave']} (mos {c['mos']}, z/s {c['distincion']} dB, {c['hz']} Hz, {c['semitonos']} st, {c['ppm']} ppm){extra}")


if __name__ == "__main__":
    import argparse

    a = argparse.ArgumentParser()
    a.add_argument("nombre", nargs="?", default="narrador")
    a.add_argument("--semillas", type=lambda s: [int(x) for x in s.split(",")])
    a.add_argument("--lenguas", type=lambda s: s.split(","))
    a.add_argument("--muestreos", type=lambda s: s.split(","))
    o = a.parse_args()
    casting(o.nombre, o.semillas, o.lenguas, o.muestreos)
