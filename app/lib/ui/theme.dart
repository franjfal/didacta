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

/// La documentación de Didacta.
///
/// Aquí y no escrita en cada botón que la abre: es una dirección que puede
/// cambiar --un dominio propio, una versión por release-- y buscarla por el
/// código sería encontrar tres y arreglar dos.
const String didactaDocs = 'https://franjfal.github.io/didacta/';

/// Donde se cuentan los problemas de Didacta.
///
/// Las incidencias del **programa**, no las del material: lo segundo es un
/// repositorio de contenido de cada uno, y lo primero es esto.
const String didactaIssues = 'https://github.com/franjfal/didacta/issues';

/// From didacta-colours.sty: the accent the PDFs use.
const Color didactaAccent = Color(0xFF55AA55);
const Color didactaAccentDark = Color(0xFF346E34);
const Color didactaInk = Color(0xFF1C1F26);

/// El gris del texto secundario.
///
/// Más oscuro que el que había (#6E7682) porque casi todo lo que lleva este
/// color es texto que hay que poder leer --rutas, recuentos, estados-- y no
/// adorno. Con el fondo de la página da 4.9:1, que pasa AA.
const Color didactaMuted = Color(0xFF62697A);

/// La línea de separación. Más clara que antes: se repite en cada fila de
/// una lista de dos mil, y a #DDE1E6 la pantalla se llenaba de rayas.
const Color didactaRule = Color(0xFFE6E8E4);

/// El fondo de la página, y el de una tarjeta encima.
///
/// La tarjeta es blanca y la página no, que es lo que hace que una tarjeta
/// se lea como tal sin ponerle sombra. Antes las dos eran casi el mismo
/// blanco y la separación dependía solo del borde.
const Color didactaSurface = Color(0xFFF6F6F3);
const Color didactaCard = Color(0xFFFFFFFF);
const Color didactaPanel = Color(0xFFEFF0EC);

/// El resalte al pasar por encima y el de lo seleccionado.
///
/// Con nombre porque es la señal de que algo responde: una aplicación de
/// escritorio en la que las filas no reaccionan al ratón se siente muerta, y
/// cada pantalla inventándose su propio gris se siente descuidada.
const Color didactaHover = Color(0x0A346E34);
const Color didactaSelected = Color(0x1A346E34);

/// The theorem palette, reused so a `definition` is the same colour on screen
/// as in a compiled slide.
const Color didactaThm = Color(0xFF2D5FA0);
const Color didactaDefn = Color(0xFF5C6470);
const Color didactaEx = Color(0xFFBE8237);
const Color didactaQues = Color(0xFF1E8C96);
const Color didactaTeacher = Color(0xFFAA4B4B);

/// El añil de una orden de LaTeX: `didactaAlgo` en el PDF.
const Color didactaAlgo = Color(0xFF646EAF);

/// El morado de un corolario, y de los caracteres que LaTeX se reserva.
const Color didactaCor = Color(0xFF8C5A96);

/// El verde de una respuesta corta: `didactaAnswerRule` del PDF.
///
/// Los colores de los entornos son los de `didacta-colours.sty`, y no una
/// paleta propia de la aplicación: una respuesta del mismo color en la
/// pantalla y en el papel es un vocabulario que se aprende una vez.
const Color didactaProp = Color(0xFF3C876E);

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

/// Los radios, con nombre y en un sitio.
///
/// A 4 px todo parecía una herramienta de línea de comandos con ventanas.
/// Subirlos es el cambio más barato que hace que una interfaz densa no se
/// sienta áspera, y no cuesta una sola fila de altura.
class Radii {
  const Radii._();

  static const double control = 8;
  static const double card = 10;
  static const double chip = 7;
  static const double dialog = 14;
  static const double small = 5;
}

/// El ritmo vertical. Cuatro valores, no catorce.
class Space {
  const Space._();

  static const double tight = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 18;
}

ThemeData didactaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: didactaAccent,
    brightness: Brightness.light,
    surface: didactaSurface,
  );

  // La escala tipográfica, en un sitio.
  //
  // Antes cada pantalla ponía su `fontSize`, y había once tamaños distintos
  // entre 10.5 y 17 sin que ninguno significara nada. Cinco pasos con nombre
  // bastan, y que el tema los tenga significa que un `Text` sin estilo ya
  // sale bien en lugar de salir con el de Material.
  const body = TextStyle(fontSize: 13, height: 1.45, color: didactaInk);
  final text = TextTheme(
    // Los títulos, con el interletrado cerrado: a peso 600 y tamaño grande,
    // el espaciado por defecto de la fuente del sistema se abre demasiado.
    headlineSmall: const TextStyle(
      fontSize: 21,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: didactaInk,
    ),
    titleLarge: const TextStyle(
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: didactaInk,
    ),
    titleMedium: const TextStyle(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: didactaInk,
    ),
    bodyLarge: body.copyWith(fontSize: 13.5),
    bodyMedium: body,
    bodySmall: const TextStyle(fontSize: 12, height: 1.4, color: didactaMuted),
    labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    labelMedium: const TextStyle(fontSize: 12, color: didactaMuted),
    labelSmall: const TextStyle(
      fontSize: 11,
      letterSpacing: 0.2,
      color: didactaMuted,
    ),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: didactaSurface,
    visualDensity: VisualDensity.compact,
    textTheme: text,
    // El resalte del ratón, uno para toda la aplicación. En escritorio es la
    // señal de que algo se puede pulsar, y sin ella una lista se siente
    // muerta.
    hoverColor: didactaHover,
    splashColor: didactaSelected,
    highlightColor: Colors.transparent,

    // Casi plano: sigue sin haber sombras en las listas --miles de filas con
    // sombra son ruido-- pero lo que flota por encima de la página (un
    // diálogo, un menú) sí la lleva, porque sin ella no se distingue de lo
    // que hay debajo.
    appBarTheme: AppBarTheme(
      backgroundColor: didactaSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: const IconThemeData(color: didactaInk, size: 20),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: didactaCard,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: didactaRule),
        borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 8,
      shadowColor: didactaInk.withValues(alpha: 0.18),
      backgroundColor: didactaCard,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.dialog)),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        elevation: const WidgetStatePropertyAll(6),
        backgroundColor: const WidgetStatePropertyAll(didactaCard),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            side: const BorderSide(color: didactaRule),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 6,
      color: didactaCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: didactaRule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),
    drawerTheme: const DrawerThemeData(
      elevation: 0,
      backgroundColor: didactaPanel,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      elevation: 0,
      backgroundColor: didactaPanel,
      indicatorColor: didactaSelected,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: didactaAccentDark,
      ),
      unselectedLabelTextStyle: const TextStyle(
        fontSize: 11,
        color: didactaMuted,
      ),
      selectedIconTheme: const IconThemeData(
        size: 20,
        color: didactaAccentDark,
      ),
      unselectedIconTheme: const IconThemeData(size: 20, color: didactaMuted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      elevation: 0,
      backgroundColor: didactaSurface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      elevation: 6,
      behavior: SnackBarBehavior.floating,
      backgroundColor: didactaInk,
      contentTextStyle: const TextStyle(
        fontSize: 13,
        height: 1.4,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      insetPadding: const EdgeInsets.all(Space.medium),
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
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: didactaCard,
      hintStyle: const TextStyle(fontSize: 13, color: didactaMuted),
      labelStyle: const TextStyle(fontSize: 13, color: didactaMuted),
      helperStyle: const TextStyle(fontSize: 11.5, color: didactaMuted),
      errorStyle: const TextStyle(fontSize: 11.5, color: didactaTeacher),
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: didactaRule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: didactaRule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      // El foco, en el verde de la casa y más grueso: en un formulario con
      // cuatro campos hay que ver en cuál se está escribiendo sin buscarlo.
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: didactaAccentDark, width: 1.6),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        foregroundColor: didactaInk,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        side: const BorderSide(color: didactaRule),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: didactaInk,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: didactaMuted,
        hoverColor: didactaSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small),
        ),
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
      backgroundColor: didactaCard,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: didactaAccentDark,
      unselectedLabelColor: didactaMuted,
      indicatorColor: didactaAccentDark,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: didactaRule,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
      overlayColor: WidgetStatePropertyAll(didactaHover),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: didactaInk.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      linearMinHeight: 3,
      color: didactaAccentDark,
      linearTrackColor: didactaRule,
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

/// La altura de línea, forzada.
///
/// Sin esto, la caja de texto decide la altura de cada línea por lo que hay
/// dentro —una fórmula alta la estira— y las columnas de colores, que se
/// pintan aparte, dejan de cuadrar con el texto a partir de ahí. Con el strut
/// forzado, una línea mide lo mismo siempre y las dos capas coinciden.
const StrutStyle monoStrut = StrutStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: monoFamilies,
  fontSize: 12.5,
  height: 1.45,
  forceStrutHeight: true,
);

/// Un envoltorio que dice si el ratón está encima.
///
/// Existe porque el resalte al pasar por encima se repite en cada lista de
/// la aplicación --unidades, documentos, asignaturas, resultados-- y cada
/// pantalla resolviéndolo a su manera daba tres grises distintos y alguna
/// fila que no reaccionaba. En escritorio eso importa: una fila que no
/// responde al ratón no parece pulsable, y la mitad de esta interfaz es
/// filas pulsables.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder, this.onTap, this.cursor});

  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final MouseCursor? cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final child = MouseRegion(
      cursor:
          widget.cursor ??
          (widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click),
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: widget.builder(context, _over),
    );
    if (widget.onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: child,
    );
  }
}

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
        borderRadius: BorderRadius.circular(Radii.small),
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

/// El tipo de una unidad, con su nombre.
///
/// Un color dice «estos dos son distintos»; no dice cuál es la explicación y
/// cuál el ejercicio. En la composición de un tema esa es justo la pregunta,
/// y la respuesta cabe en cinco letras.
class KindChip extends StatelessWidget {
  const KindChip({super.key, required this.kind, this.faded = false});

  final String kind;

  /// Para una entrada desactivada, que sigue en su sitio pero no se da.
  final bool faded;

  /// Todos del mismo ancho.
  ///
  /// «teoría», «ejemplo» y «problemas» no miden lo mismo, y con el ancho del
  /// texto los títulos de al lado empiezan cada uno en un sitio: una columna
  /// de cuarenta filas en la que nada está alineado se lee peor que una sin
  /// etiquetas. Cabe la palabra más larga que usa el repositorio.
  static const double width = 74;

  @override
  Widget build(BuildContext context) {
    final colour = kindColour(kind);
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: faded ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        kindName(kind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: colour.withValues(alpha: faded ? 0.55 : 1),
        ),
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
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.07),
        border: Border(left: BorderSide(color: colour, width: 2.5)),
        // Redondeada por la derecha: el filo recto contra una tarjeta
        // redondeada era lo que hacía que una nota pareciera pegada encima.
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(Radii.control),
          bottomRight: Radius.circular(Radii.control),
        ),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.45)),
    );
  }
}

/// Una fecha como algo que se lee, en relación a ahora.
///
/// Relativo y no absoluto: de un PDF compilado lo que importa es si es de
/// hace un minuto o de marzo, y una fecha obliga a hacer esa resta.
String describeWhen(DateTime? when) {
  if (when == null) return 'en algún momento';
  final seconds = DateTime.now().difference(when).inSeconds;
  if (seconds < 90) return 'hace un momento';
  final minutes = seconds ~/ 60;
  if (minutes < 90) return 'hace $minutes min';
  final hours = minutes ~/ 60;
  if (hours < 36) return 'hace $hours h';
  return 'hace ${hours ~/ 24} días';
}
