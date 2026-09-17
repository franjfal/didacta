---
title: Para desarrolladores
description: Qué hay en el repositorio, cómo se contribuye y con qué licencia.
---

# Para desarrolladores

!!! note "Esta sección no hace falta para usar Didacta"

    Es para quien quiera compilarla, cambiarla o entender cómo está hecha por
    dentro. Si lo que buscas es preparar tus clases, lo tuyo está en
    [Empezar](../empezar/index.md) y en [La aplicación](../app/index.md).

Didacta es **software libre** bajo la
[GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html). El código, el sistema
LaTeX, el motor y esta web están en un solo repositorio:

[:octicons-mark-github-16: franjfal/didacta](https://github.com/franjfal/didacta){ .md-button }

## Qué hay dentro

```
didacta/
├── latex/                  el sistema LaTeX
│   ├── didacta-profiles.tex    ← el registro de salidas
│   ├── didacta.sty             el paquete principal
│   ├── didacta-formats.sty     \onlyslides / \onlynotes / \onlyteacher
│   ├── didacta-theorems.sty    teoremas, dos aspectos según el medio
│   ├── didacta-problems.sty    ejercicios y los cuatro niveles
│   └── lang/                   es · va · en
├── engine/didacta/         Python: modelo, perfiles, compilación, MCP
├── cli/didacta             la herramienta
├── app/                    la aplicación, en Flutter
├── web/                    esta web
├── packaging/              publicar una versión
├── examples/demo-course/   un repositorio de contenido de ejemplo
├── tests/                  los del motor
└── ARCHITECTURE.md
```

## Las tres piezas

**El sistema LaTeX** es donde vive el mecanismo de salida: qué clase se usa,
qué canal existe en cada perfil y cómo se ve un teorema en una diapositiva y
en un libro. Añadir una salida nueva es una línea en
`latex/didacta-profiles.tex`.

**El motor** es Python sin dependencias. Lee el repositorio, resuelve las
composiciones, llama a `latexmk` y genera el catálogo.

**La aplicación** es Flutter, y está partida en dos mitades que no se tocan:
`model/` y `data/` son Dart puro y se prueban sin pintar nada; `ui/` son las
pantallas.

[:octicons-arrow-right-24: La arquitectura, entera](arquitectura.md)

## Compilarla

```bash
# el motor y la herramienta: nada que instalar
./cli/didacta --help

# los tests del motor
python3 -m unittest discover -s tests

# la aplicación
cd app
flutter pub get
flutter test
flutter run -d macos
```

La versión de Flutter está fijada en `.fvmrc`, y no es «la última estable»: en
una tubería que publica binarios, «stable» es un objetivo que se mueve.

## Contribuir

Las incidencias y las propuestas van a
[GitHub Issues](https://github.com/franjfal/didacta/issues).

Lo que se espera de un cambio:

- **que pase lo que ya pasa**: `flutter analyze --fatal-infos`,
  `dart format`, `flutter test` y los tests del motor. Es lo que corre la
  integración continua en cada push;
- **que explique el porqué donde toque.** En este código los comentarios no
  dicen lo que hace la línea de al lado: dicen por qué está así y qué se rompió
  cuando no lo estaba. Un cambio que quita una rareza sin leer el comentario
  que la explica suele reintroducir el fallo que la puso ahí;
- **que no aparezca una dependencia sin motivo.** El motor no tiene ninguna, y
  eso es una propiedad que se defiende.

[:octicons-arrow-right-24: CONTRIBUTING.md](https://github.com/franjfal/didacta/blob/main/CONTRIBUTING.md)

## Publicar una versión

Tres pasos, y el número lo pone el ciclo:

```bash
python3 packaging/release.py next   # qué número va a salir
```

1. escribir esa sección en `CHANGELOG.md`;
2. Actions → **Publish Didacta Release** → Run workflow;
3. nada más.

[:octicons-arrow-right-24: Distribución, en detalle](distribucion.md)

## La licencia

GPL-3.0. En corto: puedes usarla, estudiarla, modificarla y redistribuirla, y
si distribuyes una versión modificada tienes que publicar su código con la
misma licencia.

El texto completo está en
[`LICENSE`](https://github.com/franjfal/didacta/blob/main/LICENSE).

!!! note "Tu material no es de la licencia"

    La GPL cubre **Didacta**: el código, el motor y el sistema LaTeX. Los
    apuntes que escribas con ella son tuyos y están en tus repositorios, con
    la licencia que tú les pongas o sin ninguna.
