"""¿Distingue la voz la «z» de la «s»? Un oído para el acento de España.

Nadie puede escuchar ciento cincuenta frases para comprobar que la voz no se
ha ido al seseo, así que esto lo mide. El rasgo que mejor separa el
castellano de España del español de América es la **distinción**: «hace»,
«lección» o «empezar» se dicen con /θ/ --un soplo débil entre los dientes,
sin silbido--, y «paso» o «más» con /s/, que es un silbido fuerte en los
agudos. Con seseo las dos son la misma /s/.

Así que se toman las palabras de la frase que solo tienen el sonido /θ/ y las
que solo tienen /s/, se busca en cada una su momento de más energía en los
agudos (de 4 a 11 kHz, donde silba la /s/), y se comparan: **cuántos
decibelios silba más la /s/ que la /θ/**. Con distinción, bastantes; con
seseo, casi ninguno.

Calibrado con dos voces de referencia de Piper (es_ES y es_MX) leyendo el
mismo texto: ver ``videos/voz/README.md``.
"""

from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

import numpy as np


def _plano(palabra: str) -> str:
    palabra = unicodedata.normalize("NFKD", palabra.lower())
    palabra = "".join(c for c in palabra if not unicodedata.combining(c))
    return re.sub(r"[^a-zñ]", "", palabra)


def tipo(palabra: str) -> str | None:
    """'z' si la palabra solo tiene el sonido /θ/; 's' si solo /s/."""
    p = _plano(palabra)
    zeta = "z" in p or re.search(r"c[ei]", p) is not None
    ese = "s" in p or "x" in p
    if zeta and not ese:
        return "z"
    if ese and not zeta:
        return "s"
    return None


def silbido(onda: np.ndarray, sr: int, ini: float, fin: float) -> float | None:
    """Lo más fuerte que silba un tramo en los agudos, en dB."""
    a = max(0, int((ini - 0.02) * sr))
    b = min(len(onda), int((fin + 0.02) * sr))
    tramo = onda[a:b]
    if len(tramo) < 512:
        return None
    ventana = 512
    salto = 120
    frecuencias = np.fft.rfftfreq(ventana, 1 / sr)
    banda = (frecuencias >= 4000) & (frecuencias <= min(11000, sr / 2 - 200))
    hann = np.hanning(ventana)
    mejor = -200.0
    for i in range(0, len(tramo) - ventana, salto):
        espectro = np.abs(np.fft.rfft(tramo[i : i + ventana] * hann)) ** 2
        mejor = max(mejor, 10 * np.log10(espectro[banda].sum() + 1e-12))
    return mejor


def distincion(wav: Path, palabras: list[dict]) -> dict:
    """Cuántos dB silba más la /s/ que la /θ/ en esta grabación."""
    import soundfile as sf

    onda, sr = sf.read(str(wav), dtype="float32")
    if onda.ndim > 1:
        onda = onda.mean(axis=1)
    grupos: dict[str, list[float]] = {"z": [], "s": []}
    for w in palabras:
        t = tipo(w["p"])
        if t is None:
            continue
        valor = silbido(onda, sr, w["ini"], w["fin"])
        if valor is not None:
            grupos[t].append(valor)
    if len(grupos["z"]) < 2 or len(grupos["s"]) < 2:
        return {"db": None, "z": len(grupos["z"]), "s": len(grupos["s"])}
    return {
        "db": round(float(np.median(grupos["s"]) - np.median(grupos["z"])), 1),
        "z": len(grupos["z"]),
        "s": len(grupos["s"]),
    }


def distincion_de_varias(grabaciones: list[tuple[Path, list[dict]]]) -> dict:
    """La distinción de un vídeo entero: se juntan las palabras de todas sus
    frases, que sueltas tienen pocas de cada tipo para medir nada."""
    import soundfile as sf

    grupos: dict[str, list[float]] = {"z": [], "s": []}
    for wav, palabras in grabaciones:
        onda, sr = sf.read(str(wav), dtype="float32")
        if onda.ndim > 1:
            onda = onda.mean(axis=1)
        for w in palabras:
            t = tipo(w["p"])
            if t is None:
                continue
            valor = silbido(onda, sr, w["ini"], w["fin"])
            if valor is not None:
                grupos[t].append(valor)
    if len(grupos["z"]) < 2 or len(grupos["s"]) < 2:
        return {"db": None, "z": len(grupos["z"]), "s": len(grupos["s"])}
    return {
        "db": round(float(np.median(grupos["s"]) - np.median(grupos["z"])), 1),
        "z": len(grupos["z"]),
        "s": len(grupos["s"]),
    }


def tono(wav: Path) -> dict:
    """La altura de la voz y cuánto se mueve: mediana en Hz y rango en semitonos."""
    import librosa

    onda, sr = librosa.load(str(wav), sr=16000)
    f0, _, _ = librosa.pyin(onda, fmin=60, fmax=400, sr=sr)
    f0 = f0[~np.isnan(f0)]
    if len(f0) == 0:
        return {"hz": None, "semitonos": None}
    p10, p50, p90 = np.percentile(f0, [10, 50, 90])
    return {"hz": round(float(p50)), "semitonos": round(float(12 * np.log2(p90 / p10)), 1)}


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent))
    from voz import Oido

    oido = Oido()
    for ruta in sys.argv[1:]:
        palabras = oido.palabras(Path(ruta))
        d = distincion(Path(ruta), palabras)
        t = tono(Path(ruta))
        print(f"{Path(ruta).name:32} distinción {d['db']} dB (z {d['z']}, s {d['s']}) · "
              f"{t['hz']} Hz · {t['semitonos']} st")
