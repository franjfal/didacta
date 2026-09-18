/// Copiar un fichero a donde diga quien lo pide.
///
/// Existe por el botón de guardar del visor: lo que se está mirando ya es un
/// PDF compilado, y llevárselo es copiarlo. No hace falta el motor para eso
/// --y llamarlo sería recompilar media asignatura para sacar un fichero que
/// ya está hecho--.
library;

import 'file_copy_stub.dart'
    if (dart.library.io) 'file_copy_io.dart'
    as platform;

/// Copia [from] en [to], sustituyendo lo que hubiera.
///
/// Sustituye a propósito: el diálogo de guardar ya preguntó antes de llegar
/// aquí, y volver a preguntar --o negarse-- sería discutir con una respuesta
/// que ya se dio.
Future<void> copyFile(String from, String to) => platform.copyFile(from, to);

/// Si aquí se puede guardar una copia. Falso en la web.
bool get canCopyFiles => platform.supported;
