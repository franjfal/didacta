/// Qué poner en un commit que nadie ha escrito todavía.
///
/// El botón de enviar propone un mensaje y deja editarlo. Proponerlo no es un
/// adorno: un historial en el que todo se llama «cambios» no se lee, y nadie
/// escribe un mensaje bueno en un diálogo si se lo dejas en blanco.
///
/// La propuesta sale de **qué ficheros** se tocaron, que es lo único que se
/// sabe sin preguntar. Dice la unidad cuando es una, cuántas cuando son
/// varias, y el repositorio cuando hay más de uno por medio.
library;

/// El mensaje que se propone para lo que está sin guardar.
String proposedCommitMessage(List<String> paths) {
  if (paths.isEmpty) return '';

  final units = <String>{for (final path in paths) _unitOf(path)};
  if (units.length == 1) {
    final unit = units.single;
    final languages = <String>{
      for (final path in paths)
        if (_languageOf(path) != null) _languageOf(path)!,
    };
    if (languages.length == 1) return 'Editar $unit (${languages.single})';
    return 'Editar $unit';
  }

  final areas = <String>{for (final unit in units) _areaOf(unit)};
  if (areas.length == 1 && areas.single.isNotEmpty) {
    return 'Editar ${units.length} cosas de ${areas.single}';
  }
  return 'Editar ${units.length} ficheros';
}

/// `content/a/b/es.tex` → `content/a/b`. Un `year.yaml` es su carpeta.
String _unitOf(String path) {
  final cut = path.lastIndexOf('/');
  return cut < 0 ? path : path.substring(0, cut);
}

/// El idioma, cuando el fichero es una versión de una unidad.
String? _languageOf(String path) {
  final name = path.split('/').last;
  if (!name.endsWith('.tex')) return null;
  final code = name.substring(0, name.length - 4);
  return const {'es', 'va', 'en'}.contains(code) ? code : null;
}

/// Los dos primeros tramos: `content/analysis`, `courses/am-iii`.
String _areaOf(String unit) {
  final parts = unit.split('/');
  return parts.length < 2 ? '' : '${parts[0]}/${parts[1]}';
}
