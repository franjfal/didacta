/// El repositorio de ejemplo: un curso pequeño que viaja con la aplicación.
///
/// Existe porque la primera pregunta de quien abre Didacta sin material es
/// «¿y esto cómo se ve con algo dentro?», y contestarla con un repositorio
/// vacío es no contestarla. El ejemplo trae una asignatura con un año, un
/// tema, una hoja de problemas, lecciones traducidas y otras por traducir, y
/// un README que cuenta la estructura y el porqué.
///
/// **Viaja dentro de la aplicación y no en un repositorio público** que se
/// clone, por dos razones. Una: el formato del material cambia con el motor, y
/// un ejemplo que vive aparte acaba describiendo una versión que ya no es; el
/// que va empaquetado es siempre el de esta versión. Y dos: quien lo prueba
/// tiene que poder tocarlo --compilar, traducir, congelar--, y un repositorio
/// ajeno es de solo lectura. Así que se crea uno en su cuenta, privado, y el
/// ejemplo es su primer commit.
library;

import 'package:flutter/services.dart';

import 'local_clone.dart';
import '../l10n/tr.dart';

/// Dónde están los ficheros del ejemplo entre los recursos de la aplicación.
const String exampleAssetRoot = 'assets/ejemplo/';

/// Cómo se llama el repositorio que se crea, si el nombre está libre.
const String exampleRepositoryName = 'didacta-ejemplo';

/// Los ficheros del ejemplo, por su ruta dentro del repositorio.
///
/// Salen del manifiesto de recursos y no de una lista escrita a mano: una
/// lección nueva en el ejemplo no tiene que acordarse de apuntarse aquí.
///
/// El `.gitignore` se pone siempre, esté o no entre los recursos. Flutter no
/// empaqueta los ficheros ocultos de una carpeta, y sin él lo compilado
/// acabaría en el primer `git add` de quien lo pruebe. Por lo mismo, los
/// workflows van en `github/` y se suben a `.github/`: el de la web del
/// curso, que publica en GitHub Pages lo que deja `didacta site`.
Future<Map<String, String>> loadExampleRepository({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  final files = <String, String>{};
  for (final asset in manifest.listAssets()) {
    if (!asset.startsWith(exampleAssetRoot)) continue;
    var path = asset.substring(exampleAssetRoot.length);
    if (path.startsWith('github/')) path = '.$path';
    files[path] = await assets.loadString(asset);
  }
  if (files.isEmpty) {
    throw StateError(tr('Esta copia de Didacta se ha montado sin el ejemplo.'));
  }
  files.putIfAbsent('.gitignore', () => LocalClone.ignoredFiles);
  files.putIfAbsent('.gitattributes', () => LocalClone.textAttributes);
  return files;
}
