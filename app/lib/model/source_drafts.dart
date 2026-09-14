/// Lo que se está tocando en la vista del fuente.
///
/// La vista enseña varios ficheros a la vez, así que editar en ella es editar
/// **varios ficheros**, y eso cambia tres cosas respecto al editor de una
/// unidad:
///
/// **Un borrador por fichero.** Cambiar de idioma en un fragmento no pierde lo
/// que había escrito en el otro: son ficheros distintos y los dos se guardan.
///
/// **Los `sha` se comprueban todos antes de escribir ninguno.** Un conflicto
/// en el tercer fichero no puede dejar los dos primeros escritos y el trabajo
/// a medias. No es una transacción —GitHub no las tiene— pero sí es la
/// diferencia entre fallar antes de tocar nada y fallar por la mitad.
///
/// **Deshacer va por fichero.** Eso lo da el editor de cada fragmento; aquí
/// solo viven los borradores, que es la parte que se puede probar.
library;

/// Un fichero abierto en la vista.
class SourceDraft {
  SourceDraft({
    required this.path,
    required this.loaded,
    required this.sha,
    required this.exists,
    String? text,
  }) : text = text ?? loaded;

  /// La ruta en el repositorio: a donde va lo que se escriba.
  final String path;

  /// El texto tal como se leyó, para saber si ha cambiado y para el diff.
  final String loaded;

  /// Con qué se escribe sin pisar a nadie.
  final String sha;

  /// Falso cuando el fichero todavía no existe: escribir aquí lo crea, que es
  /// como se empieza una traducción.
  final bool exists;

  String text;

  bool get isDirty => text != loaded;

  SourceDraft saved({required String text, required String sha}) =>
      SourceDraft(path: path, loaded: text, sha: sha, exists: true, text: text);
}

/// Los borradores de una vista, por ruta.
class SourceDrafts {
  final Map<String, SourceDraft> _byPath = {};

  Iterable<SourceDraft> get all => _byPath.values;

  SourceDraft? of(String path) => _byPath[path];

  bool has(String path) => _byPath.containsKey(path);

  void put(SourceDraft draft) => _byPath[draft.path] = draft;

  void remove(String path) => _byPath.remove(path);

  /// Los que han cambiado, en orden de ruta para que el commit y el diálogo
  /// digan siempre lo mismo en el mismo orden.
  List<SourceDraft> get dirty {
    final found = [
      for (final draft in _byPath.values)
        if (draft.isDirty) draft,
    ];
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  bool get isDirty => _byPath.values.any((draft) => draft.isDirty);

  /// Las rutas que han cambiado en el repositorio desde que se leyeron.
  ///
  /// [current] es el `sha` que tiene ahora cada fichero. Uno que no existía y
  /// sigue sin existir no entra: crearlo no pisa nada.
  List<String> conflicts(Map<String, String> current) {
    final found = <String>[];
    for (final draft in dirty) {
      final now = current[draft.path];
      if (now == null) continue;
      if (draft.exists && now != draft.sha) found.add(draft.path);
      if (!draft.exists && now.isNotEmpty) found.add(draft.path);
    }
    found.sort();
    return found;
  }

  /// Un mensaje de commit que se puede leer en un historial.
  ///
  /// Con los nombres de lo que se tocó, no «editar ficheros»: un historial en
  /// el que todo se llama igual no se lee.
  String suggestedMessage(String documentTitle) {
    final touched = dirty;
    if (touched.isEmpty) return '';
    if (touched.length == 1) {
      return 'Editar ${_unitOf(touched.single.path)} '
          '(${_languageOf(touched.single.path)})';
    }
    final units = <String>{for (final draft in touched) _unitOf(draft.path)};
    return 'Editar ${units.length} unidades de $documentTitle';
  }

  static String _unitOf(String path) {
    final cut = path.lastIndexOf('/');
    return cut < 0 ? path : path.substring(0, cut);
  }

  static String _languageOf(String path) {
    final name = path.split('/').last;
    return name.endsWith('.tex') ? name.substring(0, name.length - 4) : name;
  }
}
