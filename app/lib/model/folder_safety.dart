/// Qué carpetas no se mandan nunca a la Papelera desde Didacta.
///
/// Quitar un repositorio puede llevarse su carpeta, y «Restablecer» las de
/// todos. Lo que se tira es lo que dice la lista de repositorios, y esa lista
/// la puede haber escrito cualquiera: un repositorio añadido con «Añadir un
/// clon del disco» apunta a donde alguien eligió, y una ruta mal guardada
/// puede ser la carpeta de usuario entera. Así que antes de tirar nada se
/// mira que no sea, ni contenga, algo que no es de ese repositorio.
///
/// Sin `dart:io`: la decisión se prueba sin tocar ningún disco.
library;

/// Por qué no se debe mandar [folder] a la Papelera, o `null` si se puede.
///
/// [home] es la carpeta de usuario, [cloneBase] donde se clonan los
/// repositorios, [engine] donde está el motor, y [others] las carpetas de los
/// demás repositorios, que tampoco pueden ir dentro.
String? whyNotTrash(
  String folder, {
  required String home,
  required String cloneBase,
  String? engine,
  Iterable<String> others = const [],
}) {
  final target = _normal(folder);
  if (target.isEmpty || !_absolute(target)) {
    return 'no es una ruta completa ($folder)';
  }
  if (_isRoot(target)) return 'es la raíz del disco';

  final protected = <String, String>{
    if (home.isNotEmpty) _normal(home): 'tu carpeta de usuario',
    if (cloneBase.isNotEmpty)
      _normal(cloneBase): 'la carpeta donde se clonan todos',
    if (engine != null && engine.isNotEmpty) _normal(engine): 'el motor',
  };
  for (final MapEntry(key: path, value: what) in protected.entries) {
    if (path == target) return 'es $what';
    if (_inside(path, target)) return 'dentro está $what';
  }
  // Dentro de la carpeta de usuario o de la de los clones es lo normal;
  // dentro del motor o de otro repositorio, no: sería llevarse un trozo suyo.
  if (engine != null && engine.isNotEmpty && _inside(target, _normal(engine))) {
    return 'está dentro del motor';
  }
  for (final other in others) {
    final path = _normal(other);
    if (path.isEmpty || path == target) continue;
    if (_inside(path, target)) return 'dentro está otro repositorio ($other)';
    if (_inside(target, path)) {
      return 'está dentro de otro repositorio ($other)';
    }
  }
  return null;
}

/// Con barras normales, sin la del final, y en minúsculas donde el sistema
/// no distingue: `C:\Users\Ana\` y `c:/users/ana` son la misma carpeta.
String _normal(String path) {
  var value = path.trim().replaceAll(r'\', '/');
  while (value.length > 1 && value.endsWith('/') && !_isDriveRoot(value)) {
    value = value.substring(0, value.length - 1);
  }
  return _drive.hasMatch(value) ? value.toLowerCase() : value;
}

final RegExp _drive = RegExp(r'^[A-Za-z]:');

bool _absolute(String path) => path.startsWith('/') || _drive.hasMatch(path);

bool _isDriveRoot(String path) => RegExp(r'^[A-Za-z]:/?$').hasMatch(path);

bool _isRoot(String path) => path == '/' || _isDriveRoot(path);

/// Si [inner] está dentro de [outer] (y no es la misma).
bool _inside(String inner, String outer) =>
    inner.length > outer.length && inner.startsWith('$outer/');
