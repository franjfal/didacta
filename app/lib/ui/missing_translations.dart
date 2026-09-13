/// Lo que falta por traducir antes de poder compilar un documento.
///
/// La regla vieja era compilar igual y meter un aviso donde faltara la
/// traducción, con la idea de que una presentación con una lámina en otro
/// idioma es mejor que un hueco. Para una unidad suelta sigue siendo verdad;
/// para el documento que se proyecta en clase no: lo que sale es un tema en
/// valenciano con cinco páginas en castellano, y eso no se lleva a un aula.
///
/// Así que el documento no se compila en un idioma al que le falten piezas, y
/// en lugar de compilarlo se dice **cuáles** y se lleva a cada una. La lista
/// es el trabajo que queda, en orden, con un clic por fila.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../model/catalogue.dart';
import '../router.dart';
import 'theme.dart';

/// Una pieza del documento que no existe en el idioma pedido.
class MissingPiece {
  const MissingPiece({
    required this.reference,
    required this.unit,
    required this.language,
  });

  final String reference;

  /// La unidad que hay que traducir.
  final Unit? unit;

  final String language;

  bool get broken => unit == null;
}

/// Qué le falta a un documento para poder compilarse en [language].
///
/// En el orden de la composición, sin repetir: una unidad usada dos veces en
/// el mismo tema es una sola cosa que traducir.
List<MissingPiece> missingFor(
  Document document,
  Catalogue catalogue,
  String language,
) {
  final seen = <String>{};
  final missing = <MissingPiece>[];
  for (final reference in document.unitRefs) {
    if (!seen.add(reference)) continue;
    final unit = catalogue.unitByReference(reference);
    // Una referencia que no está en el catálogo no es una traducción que
    // falta: es una referencia rota, y se dice en su sitio --en la
    // composición, en rojo-- porque lo que hay que hacer con ella es otra
    // cosa. Meterla aquí haría que «traducir esto» fuera imposible de
    // terminar.
    if (unit == null) continue;
    if (unit.statusIn(language).exists) continue;
    missing.add(
      MissingPiece(reference: reference, unit: unit, language: language),
    );
  }
  return missing;
}

/// La pantalla de «esto no se puede compilar todavía».
class MissingTranslations extends StatelessWidget {
  const MissingTranslations({super.key, required this.byLanguage});

  /// Lo que falta, por idioma. Varios porque se compila en varios a la vez.
  final Map<String, List<MissingPiece>> byLanguage;

  @override
  Widget build(BuildContext context) {
    final languages = byLanguage.keys.toList();
    final total = byLanguage.values.fold<int>(0, (sum, l) => sum + l.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        Row(
          children: [
            const Icon(Icons.translate, size: 18, color: didactaTeacher),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                languages.length == 1
                    ? 'No se puede compilar en ${languages.single}'
                    : 'No se puede compilar en ${languages.join(' ni ')}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          total == 1
              ? 'Falta por traducir una de las unidades del documento. '
                    'Compilarlo daría un tema con una parte en otro idioma, '
                    'que no es algo que se pueda llevar a clase.'
              : 'Faltan por traducir $total unidades del documento. '
                    'Compilarlo daría un tema con partes en otro idioma, que '
                    'no es algo que se pueda llevar a clase.',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 16),
        for (final language in languages) ...[
          if (languages.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'En $language',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: didactaMuted,
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: didactaCard,
              border: Border.all(color: didactaRule),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Column(
              children: [
                for (final (at, piece) in byLanguage[language]!.indexed) ...[
                  if (at > 0) const Divider(height: 1),
                  _MissingRow(piece: piece),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.piece});

  final MissingPiece piece;

  @override
  Widget build(BuildContext context) {
    final unit = piece.unit;
    return Hoverable(
      // Directo a la pestaña del idioma que falta: llegar a la unidad y tener
      // que buscar la pestaña es el paso que sobra cuando vienes de una lista
      // de lo que hay que traducir.
      onTap: unit == null
          ? null
          : () => context.go(Routes.unit(unit.path, language: piece.language)),
      builder: (context, hovering) => Container(
        color: hovering ? didactaHover : null,
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Row(
          children: [
            if (unit == null)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.link_off, size: 15, color: didactaTeacher),
              )
            else ...[
              KindChip(kind: unit.kind),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit == null
                        ? '${piece.reference} (no existe)'
                        : unit.title(unit.reference),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: unit == null ? didactaTeacher : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    piece.reference,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: didactaMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (unit != null) ...[
              Text(
                'traducir a ${piece.language}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: didactaTeacher,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: didactaMuted),
            ],
          ],
        ),
      ),
    );
  }
}
