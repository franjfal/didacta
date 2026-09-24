# Contribuir a Didacta

Gracias por mirar. Didacta es software libre bajo la
[GPL-3.0](LICENSE) y las contribuciones son bienvenidas.

## Antes de escribir código

**Las incidencias y las propuestas van a
[Issues](https://github.com/franjfal/didacta/issues).** Para algo pequeño
--una errata, un mensaje confuso, un fallo con su forma de reproducirlo-- no
hace falta preguntar antes: manda el pull request. Para algo que cambie cómo
funciona una parte, abre una incidencia primero; puede haber una razón escrita
para que esté como está, y la tendrás delante antes de gastar una tarde.

## Montar el proyecto

```bash
git clone https://github.com/franjfal/didacta.git
cd didacta

# El motor y la herramienta: no hay nada que instalar
./cli/didacta --help
python3 -m unittest discover -s tests

# La aplicación
cd app
flutter pub get
flutter test
flutter run -d macos          # o -d windows, o -d linux
```

La versión de Flutter está fijada en [`.fvmrc`](.fvmrc). No es «la última
estable» a propósito: para una tubería que publica binarios, «stable» es un
objetivo que se mueve, y el compilador con el que se reparte una aplicación no
puede ser uno que nadie eligió.

Hay un repositorio de contenido de ejemplo en
[`examples/demo-course`](examples/demo-course):

```bash
cd examples/demo-course
../../cli/didacta status
../../cli/didacta build --all
```

## Lo que se comprueba en cada push

Es lo mismo que conviene ejecutar antes de mandar nada:

```bash
python3 -m unittest discover -s tests            # el motor
python3 -m unittest discover -s packaging -p 'test_*.py'

cd app
flutter analyze --fatal-infos                    # sin excepciones
dart format --output=none --set-exit-if-changed lib test tool
flutter test
flutter build web --release --dart-define=DIDACTA_INDEX=generated
```

`--fatal-infos` no es exageración: un aviso de nivel *info* que nadie arregla
se convierte en ruido que esconde el siguiente que sí importa.

## Cómo está escrito este código

Tres cosas que se notan al leerlo, y que conviene mantener:

**Los comentarios dicen el porqué, no el qué.** No explican la línea de al
lado: explican por qué está así y qué se rompió cuando no lo estaba. Si vas a
quitar una rareza, lee el comentario que la explica: casi siempre está
documentando un fallo real, y quitarla lo reintroduce.

**El motor no tiene dependencias.** Python 3.9 y la biblioteca estándar. Es
una propiedad que se defiende: permite ejecutarlo en cualquier máquina y en
cualquier runner sin un paso de instalación. Para la aplicación, una
dependencia nueva es una decisión que hay que justificar en el pull request.

**La lógica no toca widgets.** En `app/lib`, `model/` y `data/` son Dart puro
y se prueban sin pintar nada; `ui/` son las pantallas. Ese corte es lo que
permite probar lo que merece la pena probar.

## Los tests

Un cambio de comportamiento viene con un test. No por ceremonia: los tests de
este repositorio están escritos contra **datos incómodos a propósito** --una
unidad sin traducir, una composición con una referencia rota, un `unit.yaml`
lleno de `TODO` que no se pueden perder-- porque son los casos donde las cosas
se rompen de verdad. El fixture compartido está en
[`app/test/fixture.dart`](app/test/fixture.dart).

## La documentación

La web se construye desde [`web/`](web) con MkDocs Material:

```bash
cd web
pip install -r requirements.txt
mkdocs serve
```

Las capturas no están versionadas: las pinta la propia aplicación.

```bash
cd app && flutter test tool/generate_screenshots.dart
```

Y lo que ya está escrito en el repositorio --`docs/AUTHORING.md`,
`ARCHITECTURE.md`, el CHANGELOG-- **no se copia a la web**: se incluye. Si
cambias uno, la web cambia con él.

## Los mensajes de commit

En castellano o en inglés, los dos valen. Lo que importa es que digan **qué
cambia y por qué**, no qué ficheros se tocaron: eso ya lo dice el diff.

## El CHANGELOG

Solo lo escribe quien publica una versión: arriba del todo, bajo `## Próxima`
o bajo el número que dirá `python3 packaging/release.py next`.
`python3 packaging/publish.py` le pone el número que toque al publicar. Un pull
request no necesita tocarlo, ni tampoco `release.yaml`.
