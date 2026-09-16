/// El historial de un fichero, y lo que cada commit le hizo.
///
/// El material vive en git porque git es lo que sabe contestar «¿quién tocó
/// esto, cuándo, y qué cambió?». Esa respuesta estaba a un `git log` de
/// distancia y sin embargo obligaba a salir a un terminal --o a github.com--
/// con la ruta del fichero en la cabeza. Un fichero de una unidad se reescribe
/// durante años; saber qué se quitó en septiembre es tan parte de editarlo
/// como el texto que hay ahora.
///
/// Dos decisiones que conviene dejar dichas:
///
/// **El diff lo calcula git, no la aplicación.** Hay un comparador de líneas
/// propio --`line_diff.dart`-- y se usa para otra cosa: enseñar lo que un
/// guardado va a cambiar, que es comparar dos textos que la aplicación tiene
/// en la mano. Un commit es otra pregunta: puede renombrar, puede venir de una
/// fusión, puede tocar un fichero binario. Ahí lo correcto es preguntárselo a
/// git y **leer su respuesta**, que además es exactamente la que enseña
/// GitHub.
///
/// **Se leen líneas, no se adivinan.** Un diff unificado es un formato con
/// reglas, y las que importan son las de las cabeceras `@@`: de ahí salen los
/// números de línea de las dos columnas. Un visor que los cuente por su cuenta
/// se desincroniza en el primer trozo con contexto recortado.
library;

import 'line_diff.dart';

/// Un commit que tocó un fichero.
class FileCommit {
  const FileCommit({
    required this.sha,
    required this.author,
    required this.email,
    required this.when,
    required this.subject,
    this.body = '',
  });

  /// El hash completo. Es lo que se le vuelve a dar a git.
  final String sha;

  /// Los siete primeros, que es como se nombra un commit al hablar de él.
  String get shortSha => sha.length <= 7 ? sha : sha.substring(0, 7);

  final String author;
  final String email;
  final DateTime when;

  /// La primera línea del mensaje.
  final String subject;

  /// El resto, si lo hay.
  final String body;
}

/// Una tanda de líneas contiguas de un diff, con su cabecera.
class DiffHunk {
  const DiffHunk({required this.header, required this.lines});

  /// La cabecera tal cual: `@@ -14,7 +14,9 @@ \section{Normas}`.
  ///
  /// Se enseña porque lo que viene detrás de la segunda `@@` es la sección en
  /// la que cae el cambio, y eso sitúa un trozo mejor que un número de línea.
  final String header;

  final List<DiffLine> lines;

  /// Lo que dice la cabecera después de los números: dónde cae esto.
  String get context {
    final at = header.indexOf('@@', 2);
    if (at < 0) return '';
    return header.substring(at + 2).trim();
  }
}

/// Lo que un commit le hizo a un fichero.
class FileDiff {
  const FileDiff({
    required this.hunks,
    this.renamedFrom,
    this.isBinary = false,
    this.added = 0,
    this.removed = 0,
  });

  final List<DiffHunk> hunks;

  /// De dónde venía, cuando el commit lo renombró.
  final String? renamedFrom;

  /// Git no enseña el contenido de un binario, y la interfaz tampoco finge.
  final bool isBinary;

  final int added;
  final int removed;

  /// Sin trozos y sin renombrado: el commit tocó el fichero sin cambiar su
  /// contenido --un cambio de permisos-- o no lo tocó en absoluto.
  bool get isEmpty => hunks.isEmpty && renamedFrom == null && !isBinary;
}

/// Lee la salida de `git show`/`git diff` en formato unificado.
///
/// Solo lo que hace falta y nada más: las cabeceras `@@`, las líneas con su
/// signo, y las dos cosas que un diff dice fuera de los trozos --que hubo un
/// renombrado y que el fichero es binario--. Lo demás de la cabecera
/// (`index`, `---`, `+++`) no aporta nada que la pantalla vaya a enseñar.
///
/// `\\ No newline at end of file` se descarta: no es una línea del fichero, y
/// enseñarla como tal haría que el contador de líneas dijera una de más.
FileDiff parseUnifiedDiff(String text) {
  final hunks = <DiffHunk>[];
  String? renamedFrom;
  var isBinary = false;
  var added = 0;
  var removed = 0;

  String? header;
  var lines = <DiffLine>[];
  var oldLine = 0;
  var newLine = 0;

  void closeHunk() {
    if (header != null) hunks.add(DiffHunk(header: header!, lines: lines));
    header = null;
    lines = <DiffLine>[];
  }

  // El salto final deja un elemento vacío que no es una línea del diff. Sin
  // quitarlo, el último trozo se lleva una línea de contexto de más y los
  // números de las dos columnas se van uno arriba a partir de ahí.
  final all = text.split('\n');
  if (all.isNotEmpty && all.last.isEmpty) all.removeLast();

  for (final line in all) {
    if (line.startsWith('@@')) {
      closeHunk();
      final numbers = _hunkNumbers(line);
      if (numbers == null) continue;
      header = line;
      oldLine = numbers.from;
      newLine = numbers.to;
      continue;
    }

    if (header == null) {
      // Todavía en la cabecera del fichero.
      if (line.startsWith('rename from ')) {
        renamedFrom = line.substring('rename from '.length).trim();
      } else if (line.startsWith('Binary files ') ||
          line.startsWith('GIT binary patch')) {
        isBinary = true;
      }
      continue;
    }

    if (line.startsWith('\\')) continue; // `\ No newline at end of file`
    if (line.isEmpty) {
      // Una línea vacía dentro de un trozo es una línea de contexto vacía:
      // git escribe el espacio y algunos pasos por el camino lo recortan.
      lines.add(
        DiffLine(ChangeKind.kept, '', oldLine: oldLine, newLine: newLine),
      );
      oldLine += 1;
      newLine += 1;
      continue;
    }

    final body = line.substring(1);
    switch (line[0]) {
      case '+':
        lines.add(DiffLine(ChangeKind.added, body, newLine: newLine));
        newLine += 1;
        added += 1;
      case '-':
        lines.add(DiffLine(ChangeKind.removed, body, oldLine: oldLine));
        oldLine += 1;
        removed += 1;
      case ' ':
        lines.add(
          DiffLine(ChangeKind.kept, body, oldLine: oldLine, newLine: newLine),
        );
        oldLine += 1;
        newLine += 1;
      default:
        // `diff --git` de otro fichero dentro de la misma salida: se acabó
        // este. No debería pasar --se pide un solo fichero-- pero cerrar es
        // más barato que confiar.
        closeHunk();
    }
  }
  closeHunk();

  return FileDiff(
    hunks: hunks,
    renamedFrom: renamedFrom,
    isBinary: isBinary,
    added: added,
    removed: removed,
  );
}

/// Los dos primeros números de `@@ -14,7 +16,9 @@`.
({int from, int to})? _hunkNumbers(String header) {
  final match = RegExp(
    r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@',
  ).firstMatch(header);
  if (match == null) return null;
  return (from: int.parse(match.group(1)!), to: int.parse(match.group(2)!));
}
