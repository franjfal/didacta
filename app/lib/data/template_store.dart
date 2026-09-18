/// Las plantillas que no viven en ningún repositorio de contenido.
///
/// Una plantilla se guarda **en un repositorio** casi siempre: así viaja con
/// el material, la ve quien lo comparte y la protege el historial de git. Pero
/// hay dos casos en que eso no vale: el material es de otra persona y no se
/// puede escribir en él, o la plantilla es de quien enseña y no de la
/// asignatura --el membrete de su departamento, sus colores-- y no tiene por
/// qué acabar en el repositorio de nadie.
///
/// Para eso está esta carpeta, dentro de los datos del programa. Tiene la
/// misma forma que un repositorio --`templates.yaml` y `templates/*.tex`--
/// porque es lo que el motor sabe leer, y se le pasa con `--templates-from`
/// como cualquier otro directorio.
///
/// **Y no la protege nadie.** No está en git, no se sincroniza y se va con el
/// ordenador. Por eso lo primero que dice la pantalla es que se hagan copias,
/// y por eso existe [exportTo] -- que no es una función de lujo, es la única
/// red que tiene lo que se guarde aquí.
library;

import 'template_store_stub.dart'
    if (dart.library.io) 'template_store_io.dart'
    as platform;

/// Lo que puede salir mal al copiar plantillas de un sitio a otro.
class TemplateStoreException implements Exception {
  const TemplateStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class TemplateStore {
  /// La del programa, o null donde no hay disco.
  static Future<TemplateStore?> open() => platform.openStore();

  /// Si aquí se pueden guardar plantillas. Falso en la web.
  static bool get supported => platform.supported;

  /// Dónde está. Es lo que se le pasa al motor con `--templates-from`, y lo
  /// que se enseña en Ajustes: quien guarda algo aquí tiene derecho a saber
  /// en qué carpeta va a buscarlo el día que cambie de ordenador.
  String get directory;

  /// Si hay algo guardado. Sin nada, la pantalla no avisa de copias de
  /// seguridad: no hay nada que copiar.
  Future<bool> get hasAny;

  /// El contenido de un fichero suyo, o cadena vacía si no está.
  ///
  /// Vacía y no un error: un `templates.yaml` que todavía no existe es una
  /// carpeta recién estrenada, no un fallo.
  Future<String> read(String relative);

  /// Escribe uno de sus ficheros, creando lo que haga falta.
  Future<void> write(String relative, String text);

  /// Copia las plantillas a una carpeta.
  ///
  /// La carpeta entera y no un fichero comprimido: lo que sale es un
  /// `templates.yaml` y unos `.tex` que se leen, se editan y se meten en
  /// cualquier repositorio. Un zip habría que abrirlo para saber qué hay
  /// dentro.
  ///
  /// Devuelve cuántos ficheros se copiaron.
  Future<int> exportTo(String directory);

  /// Trae las plantillas de una carpeta.
  ///
  /// Lo que ya esté aquí con el mismo nombre **se conserva**: importar añade,
  /// no sustituye. Recuperar una copia de seguridad encima de lo que se ha
  /// escrito después es la forma más rápida de perder el trabajo de una
  /// tarde, y dos plantillas con el mismo id se arreglan mirándolas.
  ///
  /// Devuelve qué se trajo y qué se dejó por estar ya.
  Future<({List<String> copied, List<String> kept})> importFrom(
    String directory,
  );
}
