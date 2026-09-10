/// La respuesta de la web a compilar: no se puede.
///
/// Compilar necesita LaTeX, y un navegador no lo tiene ni puede lanzar un
/// proceso que lo tenga. La pantalla del documento y la de la unidad lo dicen
/// y dan el comando, que es más honesto que un botón que falla.
library;

import 'compiler.dart';

bool get supported => false;

Future<String?> discover({String? configured, String? repositoryPath}) async =>
    null;

Compiler makeCompiler({
  required String enginePath,
  required String repositoryPath,
}) => throw const CompileException(
  'Un navegador no puede compilar LaTeX. Usa la aplicación de escritorio, o '
  'el comando que da la pantalla del documento.',
);
