/// El workflow que compila el material en GitHub: el que va en cada
/// repositorio de contenido.
///
/// Son dos líneas que llaman al de verdad, `.github/workflows/material.yml`
/// del repositorio del motor: lo que hay que saber para compilar --los
/// paquetes de TeX, las órdenes, cómo se separa lo que se reparte de lo del
/// profesor-- es del motor y cambia con él, y copiado en cada repositorio se
/// quedaría viejo en todos. Cada uno fija la versión con la que compila, la
/// de la aplicación que lo añadió: una versión nueva de Didacta no le cambia
/// el CI a nadie hasta que lo pide.
library;

import 'app_version.dart';
import '../l10n/tr.dart';

/// Dónde va, dentro del repositorio de contenido.
const String materialWorkflowPath = '.github/workflows/material.yml';

/// Con qué versión del motor compila: la etiqueta de [app], o `main` en una
/// compilación de desarrollo, que no tiene etiqueta publicada.
String materialEngineRef(AppVersion app) =>
    app > const AppVersion(0, 0, 0) ? app.tag : 'main';

/// El workflow, para un motor en [engineOwner]/[engineRepo] y la versión
/// [engineRef].
String materialWorkflow({
  required String engineRef,
  String engineOwner = 'franjfal',
  String engineRepo = 'didacta',
}) => tr(
  '''
# Compilar el material en GitHub cada vez que se envían cambios.
#
# Lo añadió Didacta. Compila todo con el motor {0} y deja los PDF para
# descargar en la pestaña Actions, en dos paquetes:
#
#   «PDF para repartir»  lo que se puede colgar en el aula virtual: como
#                        mucho, con los resultados, y los apuntes en HTML;
#   «PDF del profesor»   todo: soluciones, notas y exámenes con su corrección.
#
# Si el índice (generated/) no está al día, lo regenera y lo guarda.
#
# Gasta minutos de GitHub Actions. Para compilar con otra versión de Didacta,
# cambia las dos etiquetas de abajo; para dejar de compilar, borra este
# fichero.
name: Compilar el material

on:
  push:
    paths-ignore: ["site/**", "generated/**"]
  workflow_dispatch:

permissions:
  contents: write

# Si se envía otra vez mientras compila, la de antes sobra.
concurrency:
  group: material-\${{ github.ref }}
  cancel-in-progress: true

jobs:
  compilar:
    uses: {1}/{2}/.github/workflows/material.yml@{3}
    with:
      engine-ref: {4}
''',
  [engineRef, engineOwner, engineRepo, engineRef, engineRef],
);

/// Si [text] es un workflow que añadió Didacta, para no ofrecer añadirlo
/// otra vez ni tocar uno que alguien ha escrito a mano.
bool isMaterialWorkflow(String text) =>
    text.contains('/.github/workflows/material.yml@');
