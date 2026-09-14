/// Un documento entero puesto en fila para poder mirarlo.
///
/// La composición dice qué unidades entran y en qué orden; cada unidad es un
/// fichero suyo. Para editar eso está bien repartido, y para **verlo** no: la
/// pregunta que se hace delante de una presentación —«¿dónde cae el corte de
/// esta diapositiva y qué queda en cada una?»— cruza los ficheros, y abrirlos
/// de uno en uno no la contesta.
///
/// Así que se leen en orden y se pegan, y cada trozo se acuerda de dónde
/// salió. Eso último es lo que hace que la vista pueda editar más adelante y
/// que un aviso sepa qué fichero nombrar.
///
/// Dos cosas que hace igual que LaTeX, a propósito:
///
/// **Si falta una traducción, usa la de referencia** y lo dice (D13). Una
/// vista con un hueco donde debería estar la unidad describe un documento que
/// no es el que se va a compilar.
///
/// **Los apartados no son texto de ningún fichero.** Viven en `year.yaml`, en
/// los tres idiomas (D23), así que aquí son una pieza aparte. Tecleados como
/// texto se escribirían en un solo idioma, que es exactamente la cabecera en
/// castellano sobre contenido en valenciano que D14 existe para evitar.
library;

import 'catalogue.dart';
import 'tex_outline.dart';

/// Una pieza de la lectura, en el orden en que se lee.
sealed class ReadingPiece {
  const ReadingPiece();
}

/// Un apartado de la composición.
class ReadingHeading extends ReadingPiece {
  const ReadingHeading({required this.part, required this.partIndex});

  /// La entrada tal cual está en la composición, con sus tres títulos.
  final CompositionPart part;

  /// Qué entrada de la estructura es, para poder volver a ella al editarla.
  final int partIndex;

  /// `section` o `subsection`.
  String get kind => part.kind;

  Map<String, String> get titles => part.titles;

  String title(String language) => part.title(language);
}

/// Lo que devuelve leer un fichero: su texto y con qué escribirlo después.
///
/// El `sha` viaja desde la lectura porque es lo que hace que guardar sea un
/// compare-and-set: sin él, escribir es sobrescribir el trabajo de otra
/// persona sin enterarse.
typedef ReadFile =
    Future<({String text, String sha})> Function(Unit unit, String language);

/// El texto de una unidad.
class ReadingFile extends ReadingPiece {
  const ReadingFile({
    required this.reference,
    required this.unit,
    required this.requestedLanguage,
    required this.language,
    required this.path,
    required this.text,
    this.sha = '',
  });

  /// Lo que dice la composición: `analysis/normed-spaces/definition`.
  final String reference;

  final Unit unit;

  /// El idioma que se pidió y el que se acabó leyendo.
  final String requestedLanguage;
  final String language;

  /// El fichero, que es a donde vuelve una edición.
  final String path;

  final String text;

  /// Con qué se escribe este fichero sin pisar a nadie.
  final String sha;

  /// Verdadero cuando esta unidad no está traducida y se está viendo otra.
  bool get isFallback => language != requestedLanguage;
}

/// Una referencia que no se pudo leer.
///
/// Se enseña, no se salta: saltarla en silencio es cómo se llega a clase con
/// un hueco en la presentación.
class ReadingGap extends ReadingPiece {
  const ReadingGap({required this.reference, required this.reason});

  final String reference;
  final String reason;
}

/// El documento leído: sus piezas en orden y el árbol de lo que llevan.
class DocumentReading {
  const DocumentReading({required this.pieces, required this.outline});

  final List<ReadingPiece> pieces;

  /// El árbol sobre el texto de los ficheros, pegados en orden.
  ///
  /// Sobre el texto pegado y no fichero a fichero: una diapositiva que se
  /// abre en una unidad y se cierra en la siguiente es una diapositiva, y
  /// leyendo por separado serían dos errores.
  final TexOutline outline;

  List<ReadingFile> get files => [
    for (final piece in pieces)
      if (piece is ReadingFile) piece,
  ];

  List<ReadingGap> get gaps => [
    for (final piece in pieces)
      if (piece is ReadingGap) piece,
  ];
}

/// Lee un documento entero.
///
/// [read] es lo único que toca el disco o la red, y entra por parámetro para
/// que esto se pueda probar sin ninguna de las dos cosas.
Future<DocumentReading> readDocument({
  required Document document,
  required Catalogue catalogue,
  required String language,
  required ReadFile read,
}) async {
  final parts = document.structure.isNotEmpty
      ? document.structure
      : [
          for (final reference in document.unitRefs)
            CompositionPart(
              kind: 'unit',
              reference: reference,
              titles: const {},
            ),
        ];

  final pieces = <ReadingPiece>[];
  var index = -1;
  for (final part in parts) {
    index += 1;
    if (part.isHeading) {
      pieces.add(ReadingHeading(part: part, partIndex: index));
      continue;
    }
    if (part.kind != 'unit' && part.kind != 'problem') continue;

    final unit = catalogue.unitByReference(part.reference);
    if (unit == null) {
      pieces.add(
        ReadingGap(reference: part.reference, reason: 'no está en el catálogo'),
      );
      continue;
    }

    final chosen = _languageFor(unit, language);
    if (chosen == null) {
      pieces.add(
        ReadingGap(
          reference: part.reference,
          reason: 'no existe en ningún idioma',
        ),
      );
      continue;
    }

    try {
      final file = await read(unit, chosen);
      pieces.add(
        ReadingFile(
          reference: part.reference,
          unit: unit,
          requestedLanguage: language,
          language: chosen,
          path: '${unit.path}/$chosen.tex',
          text: file.text,
          sha: file.sha,
        ),
      );
    } catch (thrown) {
      pieces.add(ReadingGap(reference: part.reference, reason: '$thrown'));
    }
  }

  final outline = TexOutline.of([
    for (final piece in pieces)
      if (piece is ReadingFile)
        TexSource(
          id: piece.path,
          label: piece.reference,
          text: piece.text,
          language: piece.language,
          kind: piece.unit.isProblem
              ? TexSourceKind.problem
              : TexSourceKind.unit,
        ),
  ]);

  return DocumentReading(pieces: pieces, outline: outline);
}

/// El idioma que se va a leer de verdad, como lo elige LaTeX: el pedido, y si
/// no está, el de referencia, y si tampoco, el primero que exista.
String? _languageFor(Unit unit, String language) {
  if (unit.statusIn(language).exists) return language;
  if (unit.statusIn(unit.reference).exists) return unit.reference;
  for (final code in const ['es', 'va', 'en']) {
    if (unit.statusIn(code).exists) return code;
  }
  return null;
}
