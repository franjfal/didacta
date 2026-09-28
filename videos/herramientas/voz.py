"""La voz de los vídeos: se diseña una vez y con ella se dice cada frase.

    videos/.venv/bin/python videos/herramientas/voz.py disenar narradora
    videos/.venv/bin/python videos/herramientas/voz.py locutar frases.json salida.json

Normalmente no se llama a mano: lo hace ``videos/hacer.py``.

Todo corre en local con modelos abiertos, sin ningún servicio de pago:

* **Qwen3-TTS** (Apache 2.0) pone la voz. El modelo de *diseño* la inventa a
  partir de una descripción --no es la voz de nadie-- y el modelo *base* la
  clona desde esa muestra para cada frase. Así la voz del vídeo 1 y la del 77
  es la misma, y la de un vídeo rehecho dentro de un año también.
* **Whisper** (MIT) la escucha. Un modelo de voz que genera audio como un
  modelo de lenguaje genera texto puede saltarse una palabra o repetir otra; lo
  que se oye se transcribe, se compara con el guion y, si no coincide, la frase
  se vuelve a decir con otra semilla. Nadie tiene que escuchar ciento cincuenta
  frases para encontrar la que salió mal.

Lo ya locutado se guarda en ``videos/.build/voz/`` con el texto, la voz y el
modelo en el nombre: rehacer un vídeo en el que ha cambiado una frase solo
vuelve a decir esa frase.
"""

from __future__ import annotations

import difflib
import glob
import hashlib
import json
import os
import random
import re
import sys
import time
import unicodedata
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import yaml  # noqa: E402

VIDEOS = Path(__file__).resolve().parent.parent
VOCES = VIDEOS / "voz"
CACHE = VIDEOS / ".build" / "voz"

DISENO = "Qwen3-TTS-12Hz-1.7B-VoiceDesign"
CLON = "Qwen3-TTS-12Hz-1.7B-Base"

# Sube esto si cambia algo de cómo se genera y lo guardado ya no vale.
VERSION = 1

# Cómo se muestrea al generar. «estable» es menos azar en la voz y, sobre
# todo, en el sonido: suena menos a sintético a cambio de algo de variedad.
# La voz se locuta con el mismo con el que se diseñó, que es parte de su
# carácter (lo apunta el casting en `elegida.muestreo`).
MUESTREOS = {
    "normal": {},
    "estable": {"temperature": 0.75, "top_p": 0.95, "subtalker_temperature": 0.6, "subtalker_top_p": 0.95},
}

# Por debajo de esto, lo que se oye no es lo que dice el guion.
PARECIDO_MINIMO = 0.92
INTENTOS = 4


# ------------------------------------------------------------- modelos ---


def ruta_modelo(nombre: str) -> str:
    """El modelo descargado, si está; si no, su nombre, y se descarga."""
    raiz = os.environ.get("HF_HOME", os.path.expanduser("~/.cache/huggingface"))
    encontrados = sorted(glob.glob(f"{raiz}/hub/models--Qwen--{nombre}/snapshots/*/"))
    for ruta in encontrados:
        if os.path.exists(os.path.join(ruta, "model.safetensors")):
            return ruta
    return f"Qwen/{nombre}"


def dispositivo() -> str:
    import torch

    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda:0"
    return "cpu"


def cargar(nombre: str):
    import torch
    from qwen_tts import Qwen3TTSModel

    donde = dispositivo()
    # Precisión completa también en la GPU. Con bfloat16 va más deprisa, pero
    # el sonido que decodifica sale más sintético; la voz es lo que más se
    # nota de un vídeo, y un minuto más de espera no.
    tipo = torch.float32 if os.environ.get("DIDACTA_VOZ_RAPIDA") != "1" else torch.bfloat16
    empezado = time.time()
    modelo = Qwen3TTSModel.from_pretrained(
        ruta_modelo(nombre), device_map=donde, dtype=tipo, attn_implementation="sdpa"
    )
    print(f"  {nombre} en {donde} ({time.time() - empezado:.0f} s)", flush=True)
    return modelo


def sembrar(n: int) -> None:
    import torch

    random.seed(n)
    np.random.seed(n)
    torch.manual_seed(n)


# --------------------------------------------------------------- oído ---


class Oido:
    """Whisper, para comprobar que lo que se oye es lo que dice el guion."""

    def __init__(self, modelo: str = "small") -> None:
        import whisper

        self.modelo = whisper.load_model(modelo, device="cpu")

    def transcribir(self, ruta: Path, idioma: str = "es") -> str:
        resultado = self.modelo.transcribe(str(ruta), language=idioma, fp16=False)
        return resultado["text"].strip()

    def palabras(self, ruta: Path, idioma: str = "es") -> list[dict]:
        """Cada palabra que se oye, con cuándo empieza y cuándo acaba.

        Es lo que deja al montaje engancharse a «este párrafo» en lugar de a
        un segundo escrito a mano, que dejaría de valer al volver a locutar.
        """
        resultado = self.modelo.transcribe(
            str(ruta), language=idioma, fp16=False, word_timestamps=True
        )
        return [
            {"p": w["word"].strip(), "ini": round(float(w["start"]), 3), "fin": round(float(w["end"]), 3)}
            for segmento in resultado.get("segments", [])
            for w in segmento.get("words", [])
        ]


def normalizar(texto: str) -> list[str]:
    texto = unicodedata.normalize("NFKD", texto.lower())
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    texto = re.sub(r"[^a-z0-9ñ ]+", " ", texto)
    return texto.split()


def parecido(esperado: str, oido: str) -> float:
    """Cuánto se parece lo que se oye al guion, de 0 a 1.

    Letra a letra y sin espacios: Whisper junta y separa palabras a su manera
    («en Didacta» sale «endidacta»), y eso no es un error de la voz.
    """
    a = "".join(normalizar(esperado))
    b = "".join(normalizar(oido))
    return difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()


# ---------------------------------------------------------------- audio ---


def recortar(onda: np.ndarray, sr: int, aire: float = 0.05) -> np.ndarray:
    """Quita el silencio de los extremos y deja un poco de aire.

    Las pausas entre frases las pone el montaje, no el modelo: así el ritmo
    del vídeo se decide en un sitio.
    """
    import librosa

    _, (inicio, fin) = librosa.effects.trim(onda, top_db=42, frame_length=1024, hop_length=256)
    margen = int(aire * sr)
    return onda[max(0, inicio - margen) : min(len(onda), fin + margen)]


def huella(*partes: object) -> str:
    h = hashlib.sha1()
    for parte in partes:
        h.update(repr(parte).encode("utf-8"))
    return h.hexdigest()[:16]


def leer_voz(nombre: str) -> dict:
    cfg = yaml.safe_load((VOCES / f"{nombre}.yaml").read_text(encoding="utf-8"))
    cfg["nombre"] = nombre
    cfg["muestra"] = VOCES / f"{nombre}.wav"
    return cfg


def pronunciar(texto: str) -> str:
    """Lo que se escribe de una forma y se dice de otra: «LaTeX», «látex»."""
    fichero = VOCES / "pronunciacion.yaml"
    if not fichero.exists():
        return texto
    tabla = yaml.safe_load(fichero.read_text(encoding="utf-8")) or {}
    for escrito, dicho in tabla.items():
        texto = re.sub(rf"(?<!\w){re.escape(escrito)}(?!\w)", dicho, texto)
    return texto


# ------------------------------------------------------------- diseñar ---


def disenar(nombre: str) -> None:
    """Inventa la voz a partir de su descripción y guarda la muestra."""
    cfg = leer_voz(nombre)
    modelo = cargar(DISENO)
    oido = Oido()
    mejor = None
    for intento in range(INTENTOS):
        semilla = int(cfg.get("semilla", 0)) + intento
        sembrar(semilla)
        ondas, sr = modelo.generate_voice_design(
            text=cfg["texto"], language=cfg.get("idioma", "Spanish"), instruct=cfg["descripcion"]
        )
        onda = recortar(np.asarray(ondas[0], dtype=np.float32), sr)
        prueba = CACHE / f"diseno-{nombre}-{semilla}.wav"
        prueba.parent.mkdir(parents=True, exist_ok=True)
        sf.write(prueba, onda, sr)
        oido_texto = oido.transcribir(prueba)
        nota = parecido(cfg["texto"], oido_texto)
        print(f"  semilla {semilla}: parecido {nota:.2f} · {len(onda) / sr:.1f} s", flush=True)
        if mejor is None or nota > mejor[0]:
            mejor = (nota, semilla, onda, sr, oido_texto)
        if nota >= 0.97:
            break
    nota, semilla, onda, sr, oido_texto = mejor
    sf.write(cfg["muestra"], onda, sr)
    print(f"voz «{nombre}»: {cfg['muestra']} (semilla {semilla}, parecido {nota:.2f})")
    print(f"  se oye: {oido_texto}")


# ------------------------------------------------------------- locutar ---


def locutar(frases: list[dict], nombre_voz: str) -> list[dict]:
    """Dice cada frase con la voz, o la saca de lo ya locutado.

    Cada frase: ``{"id", "texto"}``. Devuelve, por frase, el fichero, la
    duración y cuánto se parece lo que se oye al guion.
    """
    cfg = leer_voz(nombre_voz)
    if not cfg["muestra"].exists():
        raise SystemExit(
            f"Falta la muestra de la voz «{nombre_voz}». Genérala con:\n"
            f"  python3 videos/hacer.py voz {nombre_voz}"
        )
    muestra = cfg["muestra"].read_bytes()
    idioma = cfg.get("idioma", "Spanish")
    ajustes = MUESTREOS.get((cfg.get("elegida") or {}).get("muestreo", "normal"), {})
    CACHE.mkdir(parents=True, exist_ok=True)

    pendientes = []
    resultado = []
    for frase in frases:
        dicho = pronunciar(frase["texto"])
        clave = huella(VERSION, CLON, hashlib.sha1(muestra).hexdigest(), idioma, dicho, sorted(ajustes.items()))
        wav = CACHE / f"{clave}.wav"
        meta = CACHE / f"{clave}.json"
        entrada = {"id": frase["id"], "texto": frase["texto"], "dicho": dicho, "wav": str(wav)}
        if wav.exists() and meta.exists():
            entrada.update(json.loads(meta.read_text(encoding="utf-8")))
        else:
            pendientes.append((entrada, wav, meta))
        resultado.append(entrada)

    if pendientes:
        print(f"  {len(pendientes)} frase(s) por locutar, {len(frases) - len(pendientes)} ya hechas")
        modelo = cargar(CLON)
        oido = Oido()
        aviso = modelo.create_voice_clone_prompt(ref_audio=str(cfg["muestra"]), ref_text=cfg["texto"])
        for n, (entrada, wav, meta) in enumerate(pendientes, 1):
            mejor = None
            for intento in range(INTENTOS):
                semilla = int(huella(entrada["dicho"])[:6], 16) + intento
                sembrar(semilla)
                ondas, sr = modelo.generate_voice_clone(
                    text=entrada["dicho"], language=idioma, voice_clone_prompt=aviso, **ajustes
                )
                onda = recortar(np.asarray(ondas[0], dtype=np.float32), sr)
                sf.write(wav, onda, sr)
                se_oye = oido.transcribir(wav)
                nota = parecido(entrada["dicho"], se_oye)
                # Un modelo que se enrolla dice más de lo escrito; uno que se
                # atasca, menos. Las dos cosas salen en el parecido, pero una
                # frase que dura el triple de lo razonable se descarta igual.
                razonable = len(onda) / sr < 0.12 * len(entrada["dicho"]) + 1.5
                if not razonable:
                    nota = min(nota, 0.5)
                if mejor is None or nota > mejor[0]:
                    mejor = (nota, onda.copy(), sr, se_oye, semilla)
                if nota >= PARECIDO_MINIMO:
                    break
                print(f"    repito «{entrada['id']}» (parecido {nota:.2f}: «{se_oye}»)", flush=True)
            nota, onda, sr, se_oye, semilla = mejor
            sf.write(wav, onda, sr)
            datos = {
                "duracion": round(len(onda) / sr, 3),
                "parecido": round(nota, 3),
                "se_oye": se_oye,
                "semilla": semilla,
                "palabras": oido.palabras(wav),
            }
            meta.write_text(json.dumps(datos, ensure_ascii=False, indent=1), encoding="utf-8")
            entrada.update(datos)
            aviso_bajo = "  ← revisar" if nota < PARECIDO_MINIMO else ""
            print(f"  [{n}/{len(pendientes)}] {entrada['id']}: {datos['duracion']:.1f} s, parecido {nota:.2f}{aviso_bajo}", flush=True)
    return resultado


def main(argv: list[str]) -> None:
    if len(argv) >= 2 and argv[0] == "disenar":
        disenar(argv[1])
    elif len(argv) >= 3 and argv[0] == "locutar":
        pedido = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
        hecho = locutar(pedido["frases"], pedido["voz"])
        Path(argv[2]).write_text(json.dumps(hecho, ensure_ascii=False, indent=1), encoding="utf-8")
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
