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
import 'package:flutter_localizations/flutter_localizations.dart';

import '../model/catalogue.dart';
import '../l10n/tr.dart';

// En el modelo, para que el estado de la sesión no dependa de la interfaz;
// de aquí se siguen usando igual.
export '../model/catalogue.dart' show statusName;

/// La interfaz está en castellano, así que Material también: el menú de
/// cortar y pegar del editor salía en inglés («Cut», «Copy», «Paste») porque
/// Material no sabía en qué idioma estaba. Lo que se escribe --las lecciones--
/// va en el idioma que sea; esto es solo lo de la aplicación.
const Locale didactaLocale = Locale('es');

/// Los de la interfaz: castellano, valenciano --con el catalán de Material--
/// e inglés. Ver `l10n/tr.dart`.
const List<Locale> didactaLocales = [Locale('es'), Locale('ca'), Locale('en')];

const List<LocalizationsDelegate<Object>> didactaLocalizations = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

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

/// Los colores de Didacta, con nombre: los de la versión clara y los de la
/// oscura.
///
/// **Van en el tema**, como una `ThemeExtension`: se leen con
/// `context.palette.muted`, `context.palette.card`… y quien los lee depende
/// del tema, así que cambiar de modo es cambiar el tema y cada widget que
/// pinta con ellos se vuelve a construir solo, sin perder lo que haya a medio
/// escribir. Un pintor, que no tiene contexto, la recibe de quien lo crea.
///
/// Antes eran nombres globales --`didactaMuted`-- que leían de una variable, y
/// cambiar de modo obligaba a recorrer el árbol entero marcándolo todo para
/// reconstruir: lo que se escapaba seguía pintado en el otro modo.
///
/// La oscura no es la clara invertida. El fondo es un gris casi negro con un
/// punto de verde --el de la marca--, las tarjetas suben un escalón de luz en
/// lugar de bajar, y los colores de los entornos se aclaran lo justo para
/// leerse sobre oscuro sin dejar de ser los del PDF: una definición sigue
/// siendo azul, solo que un azul que se ve.
@immutable
class DidactaPalette extends ThemeExtension<DidactaPalette> {
  const DidactaPalette({
    required this.brightness,
    required this.accent,
    required this.accentDark,
    required this.onAccent,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.rule,
    required this.surface,
    required this.card,
    required this.panel,
    required this.hover,
    required this.selected,
    required this.shadow,
    required this.thm,
    required this.defn,
    required this.ex,
    required this.ques,
    required this.teacher,
    required this.algo,
    required this.cor,
    required this.prop,
    required this.violet,
    required this.sand,
    required this.pending,
    required this.diffAddedBack,
    required this.diffAddedGutter,
    required this.diffAddedWord,
    required this.diffRemovedBack,
    required this.diffRemovedGutter,
    required this.diffRemovedWord,
    required this.track,
    required this.sketch,
    required this.terminal,
    required this.pdfBackdrop,
  });

  final Brightness brightness;

  /// El verde de la marca, y el que se usa para texto, bordes y botones.
  final Color accent;
  final Color accentDark;

  /// Lo que va encima de un botón relleno de [accentDark].
  final Color onAccent;

  /// El texto, el secundario y el de lo que no está.
  final Color ink;
  final Color muted;
  final Color faint;

  final Color rule;

  /// La página, una tarjeta encima, y el carril y los paneles de al lado.
  final Color surface;
  final Color card;
  final Color panel;

  /// El resalte al pasar por encima y el de lo seleccionado.
  final Color hover;
  final Color selected;

  /// De qué color es una sombra. En oscuro, negro de verdad: una sombra gris
  /// sobre un fondo casi negro sería más clara que lo que tapa.
  final Color shadow;

  /// Los de los entornos, de `didacta-colours.sty`.
  final Color thm;
  final Color defn;
  final Color ex;
  final Color ques;
  final Color teacher;
  final Color algo;
  final Color cor;
  final Color prop;

  /// Dos tipos de unidad que no tienen color en el PDF.
  final Color violet;
  final Color sand;

  /// El ámbar del número de lo que falta por traducir.
  final Color pending;

  /// Los verdes y los rojos de un diff: la fila, su margen, y las palabras
  /// que cambiaron dentro de ella. Claros a propósito: lo que tiene que
  /// leerse es el texto, y un fondo saturado detrás de LaTeX en monoespaciada
  /// cansa a los diez segundos.
  final Color diffAddedBack;
  final Color diffAddedGutter;
  final Color diffAddedWord;
  final Color diffRemovedBack;
  final Color diffRemovedGutter;
  final Color diffRemovedWord;

  /// La vía de una barra de progreso: lo que no está hecho.
  final Color track;

  /// El gris de las rayas que dicen «aquí hay texto» en los dibujos.
  final Color sketch;

  /// El fondo de una línea de órdenes: oscuro en los dos modos, porque una
  /// terminal clara no se lee como terminal.
  final Color terminal;

  /// Detrás de un PDF: gris, para que una página blanca tenga bordes; en
  /// oscuro, casi negro.
  final Color pdfBackdrop;

  bool get isDark => brightness == Brightness.dark;

  /// Lo que va encima de [pending]: el número del carril. Blanco sobre ese
  /// ámbar se quedaba en 3:1 en claro; oscuro, en los dos modos, pasa de 5.
  Color get onPending => isDark ? onAccent : ink;

  /// One colour per translation state, used everywhere that state is shown.
  Color status(TranslationStatus status) => switch (status) {
    TranslationStatus.source => accentDark,
    TranslationStatus.reviewed => prop,
    TranslationStatus.translated => thm,
    TranslationStatus.draft => ex,
    TranslationStatus.outdated => teacher,
    TranslationStatus.missing => faint,
  };

  /// Colour per unit kind, so a listing mixing theory and problems is
  /// readable without reading the column.
  Color kind(String kind) => switch (kind) {
    'problem' || 'exam' => ex,
    'handout' => ques,
    'seminar' || 'practical' => thm,
    'activity' || 'experiment' => violet,
    'history' => muted,
    'example' => sand,
    _ => defn,
  };

  /// El color de un repositorio en esta paleta, con contraste de texto sobre
  /// la página.
  Color repo(int value) => _repoColourIn(this, value);

  /// Un color diluido sobre la tarjeta: el fondo de una cabecera, de un
  /// aviso, de una fila marcada.
  ///
  /// Mezclado y no con transparencia, porque encima de otra cosa que no sea
  /// la tarjeta una transparencia sale de otro tono, y en oscuro un verde
  /// claro al ocho por ciento sobre casi negro se ve gris.
  Color tint(Color colour, [double amount = 0.08]) =>
      Color.alphaBlend(colour.withValues(alpha: amount), card);

  /// Nada que cambiar: una paleta es una de las dos, entera.
  @override
  DidactaPalette copyWith() => this;

  /// De una a otra, color a color. Material anima el cambio de tema, y una
  /// paleta que saltara a mitad se vería cambiar delante del resto.
  @override
  DidactaPalette lerp(covariant DidactaPalette? other, double t) {
    if (other == null || identical(other, this)) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return DidactaPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      accent: c(accent, other.accent),
      accentDark: c(accentDark, other.accentDark),
      onAccent: c(onAccent, other.onAccent),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      rule: c(rule, other.rule),
      surface: c(surface, other.surface),
      card: c(card, other.card),
      panel: c(panel, other.panel),
      hover: c(hover, other.hover),
      selected: c(selected, other.selected),
      shadow: c(shadow, other.shadow),
      thm: c(thm, other.thm),
      defn: c(defn, other.defn),
      ex: c(ex, other.ex),
      ques: c(ques, other.ques),
      teacher: c(teacher, other.teacher),
      algo: c(algo, other.algo),
      cor: c(cor, other.cor),
      prop: c(prop, other.prop),
      violet: c(violet, other.violet),
      sand: c(sand, other.sand),
      pending: c(pending, other.pending),
      diffAddedBack: c(diffAddedBack, other.diffAddedBack),
      diffAddedGutter: c(diffAddedGutter, other.diffAddedGutter),
      diffAddedWord: c(diffAddedWord, other.diffAddedWord),
      diffRemovedBack: c(diffRemovedBack, other.diffRemovedBack),
      diffRemovedGutter: c(diffRemovedGutter, other.diffRemovedGutter),
      diffRemovedWord: c(diffRemovedWord, other.diffRemovedWord),
      track: c(track, other.track),
      sketch: c(sketch, other.sketch),
      terminal: c(terminal, other.terminal),
      pdfBackdrop: c(pdfBackdrop, other.pdfBackdrop),
    );
  }

  static const DidactaPalette light = DidactaPalette(
    brightness: Brightness.light,
    // From didacta-colours.sty: the accent the PDFs use.
    accent: Color(0xFF55AA55),
    accentDark: Color(0xFF346E34),
    onAccent: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1F26),
    // Más oscuro que el que había (#6E7682) porque casi todo lo que lleva
    // este color es texto que hay que poder leer --rutas, recuentos,
    // estados-- y no adorno. Con el fondo de la página da 4.9:1, que pasa AA.
    muted: Color(0xFF62697A),
    faint: Color(0xFF9AA1AB),
    // Más clara que antes: se repite en cada fila de una lista de dos mil, y
    // a #DDE1E6 la pantalla se llenaba de rayas.
    rule: Color(0xFFE4E7E2),
    // La tarjeta es blanca y la página no, que es lo que hace que una tarjeta
    // se lea como tal sin ponerle sombra.
    surface: Color(0xFFF6F7F4),
    card: Color(0xFFFFFFFF),
    panel: Color(0xFFEEF0EB),
    hover: Color(0x0A346E34),
    selected: Color(0x1A346E34),
    shadow: Color(0xFF1C1F26),
    thm: Color(0xFF2D5FA0),
    defn: Color(0xFF5C6470),
    ex: Color(0xFFBE8237),
    ques: Color(0xFF1E8C96),
    teacher: Color(0xFFAA4B4B),
    algo: Color(0xFF646EAF),
    cor: Color(0xFF8C5A96),
    prop: Color(0xFF3C876E),
    violet: Color(0xFF7A5FAF),
    sand: Color(0xFF9A7B4F),
    pending: Color(0xFFC08A3E),
    diffAddedBack: Color(0xFFE9F6EC),
    diffAddedGutter: Color(0xFFCFEAD8),
    diffAddedWord: Color(0xFFBDE3C8),
    diffRemovedBack: Color(0xFFFBECEC),
    diffRemovedGutter: Color(0xFFF2D4D4),
    diffRemovedWord: Color(0xFFF0C2C2),
    track: Color(0xFFDCE0E4),
    sketch: Color(0xFFDADDD6),
    terminal: Color(0xFF1B1E24),
    pdfBackdrop: Color(0xFF52565C),
  );

  static const DidactaPalette dark = DidactaPalette(
    brightness: Brightness.dark,
    accent: Color(0xFF5FB85F),
    // El verde claro, para leerse sobre oscuro. Un botón relleno de este
    // verde lleva el texto oscuro, como en cualquier tema oscuro de Material.
    accentDark: Color(0xFF8FCF8C),
    onAccent: Color(0xFF0F1D10),
    ink: Color(0xFFE6E9E4),
    // 6.8:1 sobre la página: el secundario tiene que seguir leyéndose.
    muted: Color(0xFF9BA49D),
    faint: Color(0xFF687069),
    rule: Color(0xFF2B312D),
    surface: Color(0xFF141715),
    card: Color(0xFF1C201D),
    panel: Color(0xFF101311),
    hover: Color(0x128FCF8C),
    selected: Color(0x248FCF8C),
    shadow: Color(0xFF000000),
    thm: Color(0xFF82AAE3),
    defn: Color(0xFFA6AEB9),
    ex: Color(0xFFE2AB63),
    ques: Color(0xFF55C0C8),
    teacher: Color(0xFFE88A86),
    algo: Color(0xFFA0A8E6),
    cor: Color(0xFFC79AD0),
    prop: Color(0xFF6FC5A6),
    violet: Color(0xFFAE98DD),
    sand: Color(0xFFCDAB7A),
    pending: Color(0xFFD9A55B),
    diffAddedBack: Color(0xFF16291B),
    diffAddedGutter: Color(0xFF1E3A25),
    diffAddedWord: Color(0xFF2E5C39),
    diffRemovedBack: Color(0xFF2E1A1A),
    diffRemovedGutter: Color(0xFF452526),
    diffRemovedWord: Color(0xFF6B3033),
    track: Color(0xFF2E3530),
    sketch: Color(0xFF39413B),
    // Más oscuro que la tarjeta, para que no se confunda con ella.
    terminal: Color(0xFF0B0D0C),
    pdfBackdrop: Color(0xFF0B0D0C),
  );
}

/// La paleta de [BuildContext]: la del tema que tiene encima.
///
/// Leerla así, y no de los nombres globales, es lo que hace que un widget se
/// vuelva a construir solo al cambiar de modo: depende del tema, y el tema
/// cambia. Fuera de un tema de Didacta --un test que monta un `MaterialApp`
/// pelado-- es la clara.
extension DidactaPaletteOf on BuildContext {
  DidactaPalette get palette =>
      Theme.of(this).extension<DidactaPalette>() ?? DidactaPalette.light;
}

/// El texto de una línea de órdenes, sobre [DidactaPalette.terminal], que es
/// oscura en los dos modos.
const Color didactaOnTerminal = Color(0xFFD7DAE0);

/// Una etiqueta oscura encima de un PDF --el número de página--, que tiene que
/// leerse sobre el blanco de la página en los dos modos, y su texto.
const Color didactaOverlay = Color(0xB81C1F26);
const Color didactaOnOverlay = Color(0xFFFFFFFF);

/// El velo que oscurece la pantalla detrás de un paso del recorrido: el
/// mismo en los dos modos, porque lo que tiene que hacer es apagar lo que
/// no se está explicando.
const Color didactaVeil = Color(0xB3121417);

/// Los verdes de la marca, que no cambian con el modo.
///
/// El logo es el mismo en claro y en oscuro --un logo que cambia de color no
/// es un logo--, así que no lee de la paleta: son los de la marca y ya.
const Color didactaBrand = Color(0xFF346E34);
const Color didactaBrandLight = Color(0xFF5FB35F);

/// Two letters: a full word per language per row does not fit, and an icon
/// alone is not learnable.
String statusMark(TranslationStatus status) => switch (status) {
  // Las iniciales de la palabra en cada idioma: «BO» es *borrador*, y en
  // inglés un borrador es *draft*, «DR».
  TranslationStatus.source => tr('OR'),
  TranslationStatus.reviewed => tr('RV'),
  TranslationStatus.translated => tr('TR'),
  TranslationStatus.draft => tr('BO'),
  TranslationStatus.outdated => tr('DE'),
  TranslationStatus.missing => '··',
};

/// Spanish names for the kinds, since the interface is in Spanish and the
/// data is in English.
String kindName(String kind) => switch (kind) {
  'theory' => tr('teoría'),
  'problem' || 'problems' => tr('problemas'),
  'exam' => tr('examen'),
  'handout' => tr('guía'),
  'seminar' => tr('seminario'),
  'practical' => tr('práctica'),
  'activity' => tr('actividad'),
  'example' => tr('ejemplo'),
  'experiment' => tr('experimento'),
  'history' => tr('historia'),
  'notation' => tr('notación'),
  _ => kind,
};

/// La dificultad de una lección, como se lee: `easy` es «fácil».
String difficultyName(String difficulty) => switch (difficulty) {
  'easy' => tr('fácil'),
  'medium' => tr('media'),
  'hard' => tr('difícil'),
  _ => difficulty,
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

/// El tema de Material de [palette], con ella dentro como extensión: la que
/// se lee con `context.palette`.
///
/// Uno por paleta, construido la primera vez: la raíz lo pide en cada
/// redibujado, y un `ThemeData` nuevo --aunque sea igual-- hace que todo lo
/// que depende del tema se vuelva a construir.
ThemeData didactaTheme([DidactaPalette palette = DidactaPalette.light]) =>
    _themes.putIfAbsent(palette, () => _themeOf(palette));

final Map<DidactaPalette, ThemeData> _themes = {};

ThemeData _themeOf(DidactaPalette p) {
  // El esquema entero a mano sobre el de la semilla: lo que Material saca
  // solo de un verde es un tema de Material, no el de Didacta, y en oscuro
  // pinta los menús y los campos de un gris azulado que no es de nadie.
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: p.brightness,
      ).copyWith(
        primary: p.accentDark,
        onPrimary: p.onAccent,
        secondary: p.accentDark,
        onSecondary: p.onAccent,
        tertiary: p.thm,
        error: p.teacher,
        onError: p.onAccent,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.muted,
        surfaceContainerLowest: p.card,
        surfaceContainerLow: p.card,
        surfaceContainer: p.card,
        surfaceContainerHigh: p.card,
        surfaceContainerHighest: p.panel,
        outline: p.rule,
        outlineVariant: p.rule,
        shadow: p.shadow,
        inverseSurface: p.ink,
        onInverseSurface: p.surface,
        surfaceTint: Colors.transparent,
      );

  // La escala tipográfica, en un sitio.
  //
  // Antes cada pantalla ponía su `fontSize`, y había once tamaños distintos
  // entre 10.5 y 17 sin que ninguno significara nada. Cinco pasos con nombre
  // bastan, y que el tema los tenga significa que un `Text` sin estilo ya
  // sale bien en lugar de salir con el de Material.
  final body = TextStyle(fontSize: 13, height: 1.45, color: p.ink);
  final text = TextTheme(
    // Los títulos, con el interletrado cerrado: a peso 600 y tamaño grande,
    // el espaciado por defecto de la fuente del sistema se abre demasiado.
    headlineSmall: TextStyle(
      fontSize: 22,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.45,
      color: p.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: p.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: p.ink,
    ),
    bodyLarge: body.copyWith(fontSize: 13.5),
    bodyMedium: body,
    bodySmall: TextStyle(fontSize: 12, height: 1.4, color: p.muted),
    labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, color: p.muted),
    labelSmall: TextStyle(fontSize: 11, letterSpacing: 0.2, color: p.muted),
  );

  return ThemeData(
    colorScheme: scheme,
    brightness: p.brightness,
    useMaterial3: true,
    // La paleta va en el tema: quien la lee con `context.palette` depende de
    // él, y se vuelve a construir solo cuando cambia el modo.
    extensions: <ThemeExtension<dynamic>>[p],
    scaffoldBackgroundColor: p.surface,
    canvasColor: p.card,
    cardColor: p.card,
    dividerColor: p.rule,
    disabledColor: p.faint,
    visualDensity: VisualDensity.compact,
    textTheme: text,
    // El resalte del ratón, uno para toda la aplicación. En escritorio es la
    // señal de que algo se puede pulsar, y sin ella una lista se siente
    // muerta.
    hoverColor: p.hover,
    splashColor: p.selected,
    highlightColor: Colors.transparent,

    // Casi plano: sigue sin haber sombras en las listas --miles de filas con
    // sombra son ruido-- pero lo que flota por encima de la página (un
    // diálogo, un menú) sí la lleva, porque sin ella no se distingue de lo
    // que hay debajo.
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: p.ink, size: 20),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.card,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.rule),
        borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 8,
      shadowColor: p.shadow.withValues(alpha: p.isDark ? 0.45 : 0.12),
      backgroundColor: p.card,
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
        // Una sombra que se note poco: la separa el borde, y la sombra solo
        // dice que flota. Negra del todo, en las capturas de la web --donde
        // no se difumina-- salía como un marco.
        shadowColor: WidgetStatePropertyAll(
          p.shadow.withValues(alpha: p.isDark ? 0.45 : 0.14),
        ),
        backgroundColor: WidgetStatePropertyAll(p.card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            side: BorderSide(color: p.rule),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 6,
      shadowColor: p.shadow.withValues(alpha: p.isDark ? 0.45 : 0.14),
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.rule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),
    drawerTheme: DrawerThemeData(
      elevation: 0,
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      elevation: 0,
      backgroundColor: p.panel,
      indicatorColor: p.selected,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: p.accentDark,
      ),
      unselectedLabelTextStyle: TextStyle(fontSize: 11, color: p.muted),
      selectedIconTheme: IconThemeData(size: 20, color: p.accentDark),
      unselectedIconTheme: IconThemeData(size: 20, color: p.muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 0,
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      elevation: 6,
      behavior: SnackBarBehavior.floating,
      // El color del texto de fondo y el de la página para las letras: al
      // revés que todo lo demás, en los dos modos.
      backgroundColor: p.ink,
      // El verde de la **otra** paleta: el aviso va con los colores al
      // revés, y en oscuro el verde claro sobre el fondo claro del aviso se
      // quedaba en 2:1, que no se lee.
      actionTextColor: p.isDark
          ? DidactaPalette.light.accentDark
          : DidactaPalette.dark.accentDark,
      contentTextStyle: TextStyle(fontSize: 13, height: 1.4, color: p.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      insetPadding: const EdgeInsets.all(Space.medium),
    ),

    dividerTheme: DividerThemeData(space: 1, thickness: 1, color: p.rule),
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 2,
      horizontalTitleGap: 10,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.card,
      hintStyle: TextStyle(fontSize: 13, color: p.muted),
      labelStyle: TextStyle(fontSize: 13, color: p.muted),
      helperStyle: TextStyle(fontSize: 11.5, color: p.muted),
      errorStyle: TextStyle(fontSize: 11.5, color: p.teacher),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: p.rule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.rule),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      // El foco, en el verde de la casa y más grueso: en un formulario con
      // cuatro campos hay que ver en cuál se está escribiendo sin buscarlo.
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.accentDark, width: 1.6),
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
        foregroundColor: p.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        side: BorderSide(color: p.rule),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.muted,
        hoverColor: p.selected,
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
      backgroundColor: p.card,
      selectedColor: p.accentDark.withValues(alpha: 0.16),
      checkmarkColor: p.accentDark,
      side: WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? BorderSide(color: p.accentDark, width: 1.4)
            : BorderSide(color: p.rule),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        color: p.ink,
        fontWeight: FontWeight.w500,
      ),
      // El de un ChoiceChip seleccionado.
      secondaryLabelStyle: TextStyle(
        fontSize: 12,
        color: p.accentDark,
        fontWeight: FontWeight.w700,
      ),
      secondarySelectedColor: p.accentDark.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.accentDark,
      unselectedLabelColor: p.muted,
      indicatorColor: p.accentDark,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: p.rule,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
      overlayColor: WidgetStatePropertyAll(p.hover),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: p.ink.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      textStyle: TextStyle(fontSize: 12, color: p.surface),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 3,
      color: p.accentDark,
      linearTrackColor: p.rule,
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

/// El color de un repositorio en la paleta que esté puesta.
///
/// Se guardan como los de la paleta clara --son los de los entornos del PDF--
/// y se usan también para texto: en oscuro, el azul #2D5FA0 sobre casi negro
/// no se leía. Cada uno tiene su versión aclarada, la misma que usa la paleta
/// oscura para ese color; uno que no esté en la lista se aclara igual.
///
/// Y, en los dos modos, con al menos 4,5:1 sobre la página, que es lo que pide
/// un texto pequeño: el ámbar de los ejemplos se quedaba en 3:1 en claro. Si
/// no llega, se oscurece (o se aclara, en oscuro) lo justo.
Color _repoColourIn(DidactaPalette palette, int value) {
  final known = palette.isDark ? _darkRepoColours[value] : null;
  var hsl = HSLColor.fromColor(Color(known ?? value));
  if (palette.isDark && known == null && hsl.lightness < 0.7) {
    hsl = hsl.withLightness(0.7);
  }
  final step = palette.isDark ? 0.02 : -0.02;
  for (
    var i = 0;
    i < 40 && _contrast(hsl.toColor(), palette.surface) < 4.5;
    i++
  ) {
    hsl = hsl.withLightness((hsl.lightness + step).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

double _contrast(Color a, Color b) {
  final one = a.computeLuminance();
  final two = b.computeLuminance();
  return one > two ? (one + 0.05) / (two + 0.05) : (two + 0.05) / (one + 0.05);
}

/// Cada color de repositorio, en su versión de la paleta oscura.
const Map<int, int> _darkRepoColours = {
  0xFF346E34: 0xFF8FCF8C,
  0xFF2D5FA0: 0xFF82AAE3,
  0xFFBE8237: 0xFFE2AB63,
  0xFFAA4B4B: 0xFFE88A86,
  0xFF1E8C96: 0xFF55C0C8,
  0xFF8C5A96: 0xFFC79AD0,
  0xFF646EAF: 0xFFA0A8E6,
  0xFF3C876E: 0xFF6FC5A6,
};

/// Un envoltorio que dice si el ratón está encima.
///
/// Existe porque el resalte al pasar por encima se repite en cada lista de
/// la aplicación --unidades, documentos, asignaturas, resultados-- y cada
/// pantalla resolviéndolo a su manera daba tres grises distintos y alguna
/// fila que no reaccionaba. En escritorio eso importa: una fila que no
/// responde al ratón no parece pulsable, y la mitad de esta interfaz es
/// filas pulsables.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor,
    this.label,
  });

  /// Pinta el contenido; `hovering` es también «tiene el foco», para que
  /// quien va con el teclado vea lo mismo que quien pasa el ratón.
  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final MouseCursor? cursor;

  /// Lo que dice un lector de pantalla, cuando el texto de dentro no basta
  /// --una fila que es solo un icono y un número--. Sin él, lee el texto.
  final String? label;

  @override
  State<Hoverable> createState() => _HoverableState();
}

/// Las filas pulsables no recibían foco ni respondían a Intro, y un lector de
/// pantalla no sabía que eran botones: la navegación principal no se podía
/// usar sin ratón. Con [FocusableActionDetector] el tabulador llega a ellas,
/// Intro y Espacio las pulsan (son los atajos de activar de la aplicación),
/// y un borde dice dónde está el foco.
class _HoverableState extends State<Hoverable> {
  bool _over = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    if (onTap == null) {
      return MouseRegion(
        cursor: widget.cursor ?? MouseCursor.defer,
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: widget.builder(context, _over),
      );
    }
    // Un solo nodo para el lector de pantalla: el botón, su texto y que se
    // puede enfocar son la misma cosa.
    return MergeSemantics(
      child: FocusableActionDetector(
        mouseCursor: widget.cursor ?? SystemMouseCursors.click,
        onShowHoverHighlight: (on) => setState(() => _over = on),
        onShowFocusHighlight: (on) => setState(() => _focused = on),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          label: widget.label,
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              // Por delante y sin ocupar sitio: el foco no puede mover lo que
              // hay alrededor.
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      border: Border.all(
                        color: context.palette.accent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(Radii.control),
                    )
                  : null,
              child: widget.builder(context, _over || _focused),
            ),
          ),
        ),
      ),
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
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: context.palette.muted,
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
    final colour = context.palette.status(status);
    final badge = Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        // Filled when it exists, outlined when it does not: presence is the
        // first thing the eye should pick up in a column of these.
        color: status.exists ? colour.withValues(alpha: 0.12) : null,
        border: Border.all(
          color: status.exists ? colour : context.palette.rule,
        ),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        showLanguage ? '$language ${statusMark(status)}' : statusMark(status),
        style: TextStyle(
          fontSize: 11,
          height: 1.25,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: status.exists ? colour : context.palette.muted,
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
    final colour = context.palette.kind(kind);
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
    final colour = tone ?? context.palette.muted;
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
  if (when == null) return tr('en algún momento');
  final seconds = DateTime.now().difference(when).inSeconds;
  if (seconds < 90) return tr('hace un momento');
  final minutes = seconds ~/ 60;
  if (minutes < 90) return tr('hace {0} min', [minutes]);
  final hours = minutes ~/ 60;
  if (hours < 36) return tr('hace {0} h', [hours]);
  return tr('hace {0} días', [hours ~/ 24]);
}
