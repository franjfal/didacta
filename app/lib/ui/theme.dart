/// The visual language, in one place.
///
/// Two rules, both from what the interface has to do:
///
/// **Translation state has one colour scheme everywhere.** A row in the
/// library, a chip in a detail panel and a summary in the sidebar all mean the
/// same thing by the same colour, because the reader learns it once. The
/// colours match `didacta-colours.sty` where they overlap, so the screen and
/// the PDF are recognisably the same system.
///
/// **Dense before pretty.** The library is 2147 rows. Anything that adds
/// vertical space per row costs the reader a screenful of context, so the
/// defaults here are tighter than Material's.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';

/// From didacta-colours.sty: the accent the PDFs use.
const Color didactaAccent = Color(0xFF55AA55);
const Color didactaInk = Color(0xFF1C1F26);
const Color didactaMuted = Color(0xFF6E7682);

/// The theorem palette, reused so a `definition` is the same colour on screen
/// as in a compiled slide.
const Color didactaThm = Color(0xFF2D5FA0);
const Color didactaDefn = Color(0xFF5C6470);
const Color didactaEx = Color(0xFFBE8237);
const Color didactaQues = Color(0xFF1E8C96);
const Color didactaTeacher = Color(0xFFAA4B4B);

/// One colour per translation state, used everywhere that state is shown.
Color statusColour(TranslationStatus status) {
  switch (status) {
    case TranslationStatus.source:
      return didactaAccent;
    case TranslationStatus.reviewed:
      return const Color(0xFF3C876E);
    case TranslationStatus.translated:
      return didactaThm;
    case TranslationStatus.draft:
      return didactaEx;
    case TranslationStatus.outdated:
      return didactaTeacher;
    case TranslationStatus.missing:
      return const Color(0xFFB4BAC4);
  }
}

/// Two letters, because a full word per language per row does not fit and an
/// icon alone is not learnable.
String statusMark(TranslationStatus status) {
  switch (status) {
    case TranslationStatus.source:
      return 'OR';
    case TranslationStatus.reviewed:
      return 'RV';
    case TranslationStatus.translated:
      return 'TR';
    case TranslationStatus.draft:
      return 'BO';
    case TranslationStatus.outdated:
      return 'DE';
    case TranslationStatus.missing:
      return '--';
  }
}

/// The word, for a tooltip and for the sidebar summary.
String statusName(TranslationStatus status) {
  switch (status) {
    case TranslationStatus.source:
      return 'original';
    case TranslationStatus.reviewed:
      return 'revisada';
    case TranslationStatus.translated:
      return 'traducida';
    case TranslationStatus.draft:
      return 'borrador';
    case TranslationStatus.outdated:
      return 'desactualizada';
    case TranslationStatus.missing:
      return 'no existe';
  }
}

/// Colour per unit kind, so a listing mixing theory and problems is readable
/// without reading the column.
Color kindColour(String kind) {
  switch (kind) {
    case 'problem':
      return didactaEx;
    case 'handout':
      return didactaQues;
    case 'seminar':
    case 'practical':
      return didactaThm;
    case 'activity':
    case 'experiment':
      return const Color(0xFF7A5FAF);
    case 'history':
      return didactaMuted;
    default:
      return didactaDefn;
  }
}

ThemeData didactaTheme() {
  final base = ThemeData.from(
    colorScheme: ColorScheme.fromSeed(
      seedColor: didactaAccent,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );
  return base.copyWith(
    // Tighter than Material's default: the library is thousands of rows and
    // every pixel of row height is context the reader loses.
    visualDensity: VisualDensity.compact,
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 2,
      horizontalTitleGap: 10,
    ),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(),
    ),
    chipTheme: base.chipTheme.copyWith(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      labelStyle: const TextStyle(fontSize: 12),
    ),
  );
}

/// A small square carrying one language's state.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.language,
    required this.status,
    this.showLanguage = true,
  });

  final String language;
  final TranslationStatus status;
  final bool showLanguage;

  @override
  Widget build(BuildContext context) {
    final colour = statusColour(status);
    return Tooltip(
      message: '$language: ${statusName(status)}',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          // Filled when it exists, outlined when it does not: presence is the
          // first thing the eye should pick up in a column of these.
          color: status.exists ? colour.withValues(alpha: 0.14) : null,
          border: Border.all(color: colour, width: 1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          showLanguage ? '$language ${statusMark(status)}' : statusMark(status),
          style: TextStyle(
            fontSize: 11,
            height: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: status.exists ? colour : didactaMuted,
            fontWeight: status.exists ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
