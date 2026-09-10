/// The visual language: flat, dense, and consistent about state.
///
/// Three rules, each from something the interface actually has to do:
///
/// **Flat.** No elevation, no shadows, no gradients. Surfaces are separated by
/// a one-pixel rule and a change of tone. That is not a style preference: this
/// app shows thousands of rows and dozens of state badges, and shadow on any
/// of it turns a dense list into visual noise.
///
/// **Translation state has one colour scheme everywhere.** A row in the
/// library, a tab in the editor, a chip in a detail panel and a count in the
/// sidebar all mean the same thing by the same colour, so the reader learns it
/// once. The colours match `didacta-colours.sty`, so the screen and the
/// compiled PDF are recognisably the same system.
///
/// **Dense before pretty.** Every pixel of row height is a row of context the
/// reader loses. The defaults here are tighter than Material's throughout.
library;

import 'package:flutter/material.dart';

import '../model/catalogue.dart';

/// From didacta-colours.sty: the accent the PDFs use.
const Color didactaAccent = Color(0xFF55AA55);
const Color didactaAccentDark = Color(0xFF346E34);
const Color didactaInk = Color(0xFF1C1F26);
const Color didactaMuted = Color(0xFF6E7682);
const Color didactaRule = Color(0xFFDDE1E6);
const Color didactaSurface = Color(0xFFFAFAF8);
const Color didactaPanel = Color(0xFFF2F3F1);

/// The theorem palette, reused so a `definition` is the same colour on screen
/// as in a compiled slide.
const Color didactaThm = Color(0xFF2D5FA0);
const Color didactaDefn = Color(0xFF5C6470);
const Color didactaEx = Color(0xFFBE8237);
const Color didactaQues = Color(0xFF1E8C96);
const Color didactaTeacher = Color(0xFFAA4B4B);

/// One colour per translation state, used everywhere that state is shown.
Color statusColour(TranslationStatus status) => switch (status) {
  TranslationStatus.source => didactaAccentDark,
  TranslationStatus.reviewed => const Color(0xFF3C876E),
  TranslationStatus.translated => didactaThm,
  TranslationStatus.draft => didactaEx,
  TranslationStatus.outdated => didactaTeacher,
  TranslationStatus.missing => const Color(0xFF9AA1AB),
};

/// Two letters: a full word per language per row does not fit, and an icon
/// alone is not learnable.
String statusMark(TranslationStatus status) => switch (status) {
  TranslationStatus.source => 'OR',
  TranslationStatus.reviewed => 'RV',
  TranslationStatus.translated => 'TR',
  TranslationStatus.draft => 'BO',
  TranslationStatus.outdated => 'DE',
  TranslationStatus.missing => '··',
};

String statusName(TranslationStatus status) => switch (status) {
  TranslationStatus.source => 'original',
  TranslationStatus.reviewed => 'revisada',
  TranslationStatus.translated => 'traducida',
  TranslationStatus.draft => 'borrador',
  TranslationStatus.outdated => 'desactualizada',
  TranslationStatus.missing => 'no existe',
};

/// Colour per unit kind, so a listing mixing theory and problems is readable
/// without reading the column.
Color kindColour(String kind) => switch (kind) {
  'problem' => didactaEx,
  'handout' => didactaQues,
  'seminar' || 'practical' => didactaThm,
  'activity' || 'experiment' => const Color(0xFF7A5FAF),
  'history' => didactaMuted,
  'example' => const Color(0xFF9A7B4F),
  _ => didactaDefn,
};

/// Spanish names for the kinds, since the interface is in Spanish and the
/// data is in English.
String kindName(String kind) => switch (kind) {
  'theory' => 'teoría',
  'problem' => 'problemas',
  'handout' => 'guía',
  'seminar' => 'seminario',
  'practical' => 'práctica',
  'activity' => 'actividad',
  'example' => 'ejemplo',
  'experiment' => 'experimento',
  'history' => 'historia',
  'notation' => 'notación',
  _ => kind,
};

ThemeData didactaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: didactaAccent,
    brightness: Brightness.light,
    surface: didactaSurface,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: didactaSurface,
    visualDensity: VisualDensity.compact,

    // Flat: no elevation anywhere. A one-pixel rule does the separating.
    appBarTheme: const AppBarTheme(
      backgroundColor: didactaSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: didactaInk,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: didactaInk, size: 20),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: didactaRule),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      elevation: 0,
      backgroundColor: didactaSurface,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: const DrawerThemeData(
      elevation: 0,
      backgroundColor: didactaPanel,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      elevation: 0,
      backgroundColor: didactaPanel,
      indicatorColor: Color(0x2255AA55),
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: didactaAccentDark,
      ),
      unselectedLabelTextStyle: TextStyle(fontSize: 11, color: didactaMuted),
      selectedIconTheme: IconThemeData(size: 20, color: didactaAccentDark),
      unselectedIconTheme: IconThemeData(size: 20, color: didactaMuted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      elevation: 0,
      backgroundColor: didactaSurface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: didactaInk,
      contentTextStyle: TextStyle(fontSize: 13, color: Colors.white),
    ),

    dividerTheme: const DividerThemeData(
      space: 1,
      thickness: 1,
      color: didactaRule,
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 2,
      horizontalTitleGap: 10,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: didactaRule),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: didactaRule),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: didactaRule),
        textStyle: const TextStyle(fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    // Un chip seleccionado tiene que verse seleccionado.
    //
    // Esto estaba mal y se notaba justo donde más importa: los chips son el
    // control con el que se elige el tipo de una unidad, su estado de
    // traducción y qué versiones compilar, y con `backgroundColor` en blanco
    // y `selectedColor` sin poner, los dos estados se pintaban blancos. La
    // marca de verificación era la única diferencia, y en una fila de siete
    // no se lee.
    //
    // Tres señales a la vez y no una: relleno, borde y peso. Una sola es
    // frágil --el relleno se pierde en una captura, el borde a tamaño
    // pequeño-- y las tres juntas se leen de un vistazo.
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: didactaAccentDark.withValues(alpha: 0.16),
      checkmarkColor: didactaAccentDark,
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const BorderSide(color: didactaAccentDark, width: 1.4)
            : const BorderSide(color: didactaRule),
      ),
      labelStyle: const TextStyle(
        fontSize: 12,
        color: didactaInk,
        fontWeight: FontWeight.w500,
      ),
      // El de un ChoiceChip seleccionado.
      secondaryLabelStyle: const TextStyle(
        fontSize: 12,
        color: didactaAccentDark,
        fontWeight: FontWeight.w700,
      ),
      secondarySelectedColor: didactaAccentDark.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: didactaInk,
      unselectedLabelColor: didactaMuted,
      indicatorColor: didactaAccentDark,
      dividerColor: didactaRule,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: didactaInk,
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      textStyle: TextStyle(fontSize: 12, color: Colors.white),
    ),
  );
}

/// The monospace stack for paths and LaTeX. Named once so an editor and a
/// path label cannot end up in different faces.
const List<String> monoFamilies = [
  'SF Mono',
  'Menlo',
  'DejaVu Sans Mono',
  'Consolas',
  'monospace',
];

const TextStyle monoStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: monoFamilies,
  fontSize: 12.5,
  height: 1.45,
);

/// A section heading in a panel: small, spaced, quiet.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: didactaMuted,
            ),
          ),
        ),
        ?trailing,
      ],
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
    this.onTap,
  });

  final String language;
  final TranslationStatus status;
  final bool showLanguage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colour = statusColour(status);
    final badge = Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        // Filled when it exists, outlined when it does not: presence is the
        // first thing the eye should pick up in a column of these.
        color: status.exists ? colour.withValues(alpha: 0.12) : null,
        border: Border.all(color: status.exists ? colour : didactaRule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        showLanguage ? '$language ${statusMark(status)}' : statusMark(status),
        style: TextStyle(
          fontSize: 11,
          height: 1.25,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: status.exists ? colour : didactaMuted,
          fontWeight: status.exists ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );

    return Tooltip(
      message: '$language: ${statusName(status)}',
      child: onTap == null
          ? badge
          : InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: onTap,
              child: badge,
            ),
    );
  }
}

/// A short note in a panel: explains a state without looking like an error.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? didactaMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.07),
        border: Border(left: BorderSide(color: colour, width: 2)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
    );
  }
}
