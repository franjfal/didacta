/// El git que se lanza: el que encontró la comprobación de herramientas.
///
/// Se lanzaba por su nombre, y el que contestaba era el primero del PATH que
/// hereda la aplicación, que no tiene por qué ser el que Ajustes dice que
/// está bien: en macOS una aplicación abierta desde el Finder no hereda el
/// PATH del terminal, y en Windows el de Git for Windows no siempre está en
/// él. Ahora se busca igual que lo busca la comprobación --PATH, Homebrew,
/// la carpeta de Git for Windows-- y se usa esa ruta.
library;

import '../model/toolchain.dart';
import 'toolchain_io.dart' show findIn, toolDirectories;

String? _found;

/// La ruta de git, o `git` a secas si no se encuentra --y entonces el error
/// es el de siempre, que la comprobación de herramientas ya explica--.
String gitExecutable() {
  final known = _found;
  if (known != null) return known;
  final found = findIn(toolById(ToolId.git).executables, toolDirectories());
  // Solo se recuerda lo encontrado: si se instala git con la aplicación
  // abierta, la próxima vez se encuentra.
  if (found != null) _found = found.path;
  return found?.path ?? 'git';
}
