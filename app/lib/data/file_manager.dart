/// Lo que se le pide al explorador de archivos del sistema: abrir una carpeta
/// y mandar una a la Papelera.
///
/// Una clase y no dos funciones sueltas para que las pruebas pongan la suya:
/// abrir ventanas del Finder o tirar carpetas de verdad en un test no prueba
/// nada y deja basura.
library;

import 'file_manager_stub.dart'
    if (dart.library.io) 'file_manager_io.dart'
    as platform;

class FileManager {
  const FileManager();

  /// Si aquí hay explorador de archivos. En la web, no.
  bool get supported => platform.supported;

  /// El botón, dicho como lo llama cada sistema: «Abrir en el Finder».
  String get openLabel => platform.openLabel;

  /// La carpeta de usuario, que nunca se tira.
  String get home => platform.home;

  /// Abre [folder]. Devuelve si se pudo.
  Future<bool> open(String folder) => platform.openFolder(folder);

  /// Manda [folder] a la Papelera. Devuelve si ya no está donde estaba.
  ///
  /// Nunca la borra del todo: si no se puede mandar a la Papelera, se queda.
  Future<bool> trash(String folder) => platform.trashFolder(folder);
}
