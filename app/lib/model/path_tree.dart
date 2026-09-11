/// Las unidades como el árbol de carpetas que son.
///
/// La biblioteca enseña el material por categoría y tema, y a propósito **no**
/// por área: la teoría de espacios normados y sus ejercicios son la misma
/// asignatura, y separarlos obliga a mirar en dos sitios lo que se prepara
/// junto. Para elegir qué añadir a un tema hace falta lo contrario: la
/// estructura tal como está en el disco, `content/` y `problems/` incluidos,
/// que es la que alguien tiene en la cabeza cuando sabe dónde dejó una
/// lección y no cómo la tituló.
///
/// Se construye de las rutas y no de un esquema con los niveles escritos:
/// hoy todas son `área/categoría/tema/unidad`, y el día que una tenga un
/// nivel más el árbol lo enseña en lugar de perderla.
library;

import 'catalogue.dart';
import 'library_tree.dart' show humaniseSlug;

class PathNode {
  PathNode({required this.name, required this.path});

  /// El segmento: `analysis`, `normed-spaces`.
  final String name;

  /// La ruta completa hasta aquí: `content/analysis/normed-spaces`.
  final String path;

  final Map<String, PathNode> _children = {};
  final List<Unit> _units = [];

  /// Las carpetas de dentro, en orden alfabético por su nombre visible.
  List<PathNode> get children {
    final list = _children.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return List.unmodifiable(list);
  }

  /// Las unidades que cuelgan directamente de aquí, por título.
  List<Unit> units(String language) {
    final list = [..._units]
      ..sort(
        (a, b) => a
            .title(language)
            .toLowerCase()
            .compareTo(b.title(language).toLowerCase()),
      );
    return List.unmodifiable(list);
  }

  /// Cuántas unidades hay aquí dentro, contando las de las subcarpetas.
  ///
  /// Es lo que hace que una carpeta cerrada diga algo: «álgebra 224» ya
  /// responde a si merece la pena abrirla.
  late final int count =
      _units.length +
      _children.values.fold<int>(0, (sum, child) => sum + child.count);

  /// El nombre para leer. `normed-spaces` es una carpeta; «Normed spaces» es
  /// lo que alguien reconoce.
  late final String label = humaniseSlug(name);

  /// Todas las unidades de aquí para abajo, en el orden del árbol.
  List<Unit> everything(String language) => [
    for (final child in children) ...child.everything(language),
    ...units(language),
  ];
}

/// El árbol completo, con las áreas arriba.
PathNode buildPathTree(Iterable<Unit> units) {
  final root = PathNode(name: '', path: '');
  for (final unit in units) {
    final segments = unit.path.split('/');
    if (segments.length < 2) continue;
    var node = root;
    // Todos los segmentos menos el último, que es la unidad.
    for (final segment in segments.take(segments.length - 1)) {
      final path = node.path.isEmpty ? segment : '${node.path}/$segment';
      node = node._children.putIfAbsent(
        segment,
        () => PathNode(name: segment, path: path),
      );
    }
    node._units.add(unit);
  }
  return root;
}

/// La rama que lleva a una ruta, para poder abrirla de golpe.
///
/// Sirve para «enséñame dónde está esta»: con las carpetas del camino
/// abiertas, la unidad queda a la vista sin que nadie tenga que adivinar en
/// cuál estaba.
List<String> branchTo(String unitPath) {
  final segments = unitPath.split('/');
  final branch = <String>[];
  for (var i = 1; i < segments.length; i += 1) {
    branch.add(segments.take(i).join('/'));
  }
  return branch;
}
