/// Las capturas de la web, pintadas por la propia aplicación.
///
///     cd app && flutter test tool/generate_screenshots.dart
///
/// Escribe los PNG de `web/docs/img/app/`, que es lo que la documentación
/// enseña. Se ejecuta con el arnés de tests por lo mismo que
/// `generate_icons.dart`: hace falta un motor de Flutter para rasterizar, y
/// éste es **el mismo rasterizador que la aplicación**.
///
/// Por qué así y no capturando la ventana a mano:
///
/// * **se regeneran solas.** Una pantalla que cambia deja la captura vieja, y
///   una captura vieja en la documentación es peor que no tener ninguna:
///   enseña botones que ya no están. Esto corre en el despliegue de la web,
///   así que lo publicado es siempre lo que hace la versión de ahora;
/// * **no hace falta una máquina con pantalla.** Corre en un runner, sin
///   servidor gráfico, sin abrir nada y sin que nadie pulse;
/// * **los datos son los mismos que los de los tests.** El fixture de
///   `test/fixture.dart` tiene a propósito datos incómodos --una unidad sin
///   traducir, una referencia rota, un problema con un aviso-- y eso es lo que
///   hay que enseñar. Una captura con datos perfectos documenta una
///   aplicación que nadie tiene.
///
/// **Las fuentes hay que cargarlas.** En un test, Flutter no tiene ninguna
/// tipografía de verdad: lo que pinta sin cargar nada son rectángulos negros
/// donde va el texto. Se cargan del propio sistema --ninguna se copia al
/// repositorio, que sería redistribuir una fuente que no es nuestra-- y si no
/// hay ninguna de la lista, esto falla diciéndolo en lugar de escribir
/// dieciséis capturas ilegibles.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/file_history.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/welcome.dart';
import 'package:didacta_app/ui/welcome_art.dart';

import '../test/fixture.dart';

/// Dónde se escriben. Relativo a `app/`, que es desde donde corre el arnés.
const String outputDir = '../web/docs/img/app';

/// El tamaño de ventana de las capturas, en puntos.
///
/// Un portátil, y no una pantalla de escritorio: es donde se usa Didacta, y
/// una captura de 2560 puntos de ancho enseña una interfaz con el contenido
/// perdido en medio de un océano de blanco.
///
/// 1440 no es un número redondo cualquiera: la columna de texto de la web
/// mide unos 720 px, así que una captura de 1440 **es** la versión retina de
/// lo que se ve. Sale nítida sin pedirle al rasterizador el doble de píxeles.
const Size window = Size(1440, 920);

/// La densidad de la ventana que se simula.
///
/// Dos, como una pantalla retina: **la nitidez se pide aquí y no al capturar**.
/// Con esto la interfaz se rasteriza a 2880×1840 píxeles de verdad y la
/// captura sale de ahí tal cual; pedirle a `toImage` que escale es lo que se
/// queda colgado.
const double density = 2.0;

/// El factor con el que se captura. Uno: la imagen ya está rasterizada a la
/// densidad de arriba, y lo único que hace un factor mayor es no volver.
const double pixels = 1.0;

// ---------------------------------------------------------------- fuentes ---

/// Las fuentes salen del **propio SDK de Flutter**.
///
/// `bin/cache/artifacts/material_fonts/` trae Roboto en sus nueve pesos y la
/// tipografía de los iconos de Material. Es exactamente lo que la aplicación
/// usa cuando corre de verdad en Android y en Linux, y lo bastante parecido a
/// lo que usa en macOS y en Windows.
///
/// Que salgan de ahí y no del sistema tiene dos consecuencias buenas: **las
/// capturas salen iguales en cualquier máquina** --el runner de Linux y el
/// portátil de quien escribe documentación-- y no se copia al repositorio
/// ninguna fuente que no sea nuestra.
///
/// Sin esto, un test de Flutter pinta **rectángulos negros** donde va el
/// texto y cuadraditos vacíos donde van los iconos.
String _fontsDirectory() {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final candidates = <String>[
    if (root.isNotEmpty) '$root/bin/cache/artifacts/material_fonts',
  ];

  // Sin `FLUTTER_ROOT` --que lo pone `flutter test`, pero no hay por qué
  // confiar en ello-- se busca subiendo desde el binario que está
  // ejecutando esto, que vive dentro del mismo `bin/cache`.
  var directory = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i += 1) {
    candidates.add('${directory.path}/artifacts/material_fonts');
    candidates.add('${directory.path}/bin/cache/artifacts/material_fonts');
    directory = directory.parent;
  }

  for (final candidate in candidates) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'No encuentro las fuentes del SDK de Flutter.\n'
    'Se buscan en FLUTTER_ROOT/bin/cache/artifacts/material_fonts y subiendo '
    'desde ${Platform.resolvedExecutable}.\n'
    'Sin ellas, un test pinta rectángulos negros donde va el texto.',
  );
}

/// Los pesos de Roboto que se registran, y bajo qué nombres.
///
/// **También como `Ahem`**, y eso no es un descuido: es la fuente de caja que
/// el arnés de tests pone por defecto, así que todo lo que no diga una familia
/// explícita --las etiquetas del carril, los estilos de los componentes de
/// Material-- acaba en ella. Registrándola con una tipografía de verdad, la
/// captura sale como la aplicación y **sin tocar el tema**: lo que se
/// fotografía es lo que hay, no una variante para la foto.
const List<String> _robotoNames = ['Roboto', 'Ahem', 'FlutterTest'];

const List<String> _robotoFiles = [
  'Roboto-Regular.ttf',
  'Roboto-Medium.ttf',
  'Roboto-Bold.ttf',
  'Roboto-Light.ttf',
  'Roboto-Italic.ttf',
  'Roboto-BoldItalic.ttf',
];

/// Y la monoespaciada, que la interfaz pide por su nombre genérico.
const List<String> _monoNames = ['monospace', 'Menlo', 'Consolas'];

Future<void> _register(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Carga las tipografías, o falla diciendo por qué.
Future<void> loadFonts() async {
  final directory = _fontsDirectory();

  final roboto = [
    for (final name in _robotoFiles)
      if (File('$directory/$name').existsSync()) '$directory/$name',
  ];
  if (roboto.isEmpty) {
    throw StateError('En $directory no hay ningún Roboto.');
  }
  for (final family in _robotoNames) {
    await _register(family, roboto);
  }

  // La monoespaciada del sistema, que el SDK no trae. Si no hay ninguna, el
  // texto en monoespaciada cae en Roboto: se lee, y no vale la pena parar una
  // generación de capturas por eso.
  const mono = [
    '/System/Library/Fonts/Supplemental/Andale Mono.ttf',
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
  ];
  final found = mono.where((path) => File(path).existsSync()).take(1).toList();
  for (final family in _monoNames) {
    await _register(family, found.isEmpty ? roboto.take(1).toList() : found);
  }

  // Los iconos. Sin esto, cada icono de la interfaz es un cuadrado vacío, que
  // en una captura de una aplicación con un carril de iconos es la mitad de
  // lo que se está enseñando.
  final icons = '$directory/MaterialIcons-Regular.otf';
  if (File(icons).existsSync()) {
    await _register('MaterialIcons', [icons]);
  }
}

// ----------------------------------------------------------------- pintar ---

/// Lo que hay que hacer en una pantalla antes de capturarla, si hay algo.
typedef Prepare = Future<void> Function(WidgetTester tester);

/// Una captura: su nombre de fichero, a qué dirección va y qué hacer allí.
class Shot {
  const Shot(this.name, this.route, {this.prepare, this.note});

  final String name;
  final String route;
  final Prepare? prepare;

  /// Para el resumen que se imprime al final.
  final String? note;
}

final GlobalKey _frame = GlobalKey();

/// Deja que todo lo que se lanzó al construir la pantalla termine.
///
/// A mano y no con `pumpAndSettle`: varias pantallas tienen una animación
/// continua --el progreso de una comprobación, el cursor de un editor-- y
/// `pumpAndSettle` con una de ésas delante no vuelve nunca.
Future<void> settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Tres detalles que costaron una mañana, porque los tres fallan igual: el
  // test se queda parado, sin error, sin excepción y sin salida, hasta que
  // expira.
  //
  // **Dentro de `runAsync`.** Rasterizar y codificar un PNG es trabajo del
  // motor de verdad, y dentro de un test el reloj es falso: ese futuro no se
  // completa nunca esperándolo con el reloj falso.
  //
  // **Con el factor a uno.** La nitidez se pide en la ventana --[density]--
  // y no aquí: `toImage` con un factor mayor que uno tampoco vuelve.
  //
  // **Y escribiendo el fichero en síncrono.** `writeAsBytes` es otro futuro
  // de verdad, y fuera de `runAsync` se queda esperando igual.
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixels);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes;
  });
  if (png == null) throw StateError('no se pudo codificar $name');

  final file = File('$outputDir/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png.buffer.asUint8List(), flush: true);
  stdout.writeln(
    '  ${(png.lengthInBytes / 1024).round().toString().padLeft(5)} kB  '
    '${file.path}',
  );
}

/// La familia con la que se pinta el texto de las capturas.
///
/// Roboto, que es la que trae el SDK y la que Flutter usa por defecto en
/// Android y en Linux. En macOS la aplicación sale con la del sistema y en
/// Windows con la suya; ninguna de las tres es «la» tipografía de Didacta, así
/// que la captura usa la que está garantizada en cualquier máquina.
const String shotFamily = 'Roboto';

/// El tema de las capturas: el de la aplicación, con la familia puesta.
///
/// Hay que ponerla a mano en los temas de los componentes y no basta con
/// `textTheme.apply`, y la razón se ve en una captura: los estilos que un tema
/// de componente declara --las etiquetas del carril, el texto de un botón, el
/// `hint` de un campo-- **no heredan** del tema de texto. En la aplicación de
/// verdad eso da igual, porque sin familia el sistema pone la suya; en un
/// test, lo que pone es la fuente de caja, y esas etiquetas salían como
/// rectángulos negros mientras el resto se leía perfectamente.
ThemeData shotTheme() {
  final base = didactaTheme();
  TextStyle? family(TextStyle? style) =>
      style?.copyWith(fontFamily: shotFamily);
  WidgetStateProperty<TextStyle?>? property(
    WidgetStateProperty<TextStyle?>? value,
  ) => value == null
      ? null
      : WidgetStatePropertyAll<TextStyle?>(family(value.resolve(const {})));
  ButtonStyle? button(ButtonStyle? style) =>
      style?.copyWith(textStyle: property(style.textStyle));

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: shotFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: shotFamily),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      selectedLabelTextStyle: family(
        base.navigationRailTheme.selectedLabelTextStyle,
      ),
      unselectedLabelTextStyle: family(
        base.navigationRailTheme.unselectedLabelTextStyle,
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      labelTextStyle: property(base.navigationBarTheme.labelTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(base.textButtonTheme.style),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: family(base.tabBarTheme.labelStyle),
      unselectedLabelStyle: family(base.tabBarTheme.unselectedLabelStyle),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: family(base.chipTheme.labelStyle),
      secondaryLabelStyle: family(base.chipTheme.secondaryLabelStyle),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      hintStyle: family(base.inputDecorationTheme.hintStyle),
      labelStyle: family(base.inputDecorationTheme.labelStyle),
      helperStyle: family(base.inputDecorationTheme.helperStyle),
      errorStyle: family(base.inputDecorationTheme.errorStyle),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: family(base.listTileTheme.titleTextStyle),
      subtitleTextStyle: family(base.listTileTheme.subtitleTextStyle),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      textStyle: family(base.tooltipTheme.textStyle),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      contentTextStyle: family(base.snackBarTheme.contentTextStyle),
    ),
  );
}

/// La sesión con la que se pintan: la del fixture de los tests.
Future<FakeSession> buildSession() async {
  final catalogue = catalogueWith(defaultUnits());
  final clone = FakeClone(behind: 2);
  // Un historial de verdad para la pestaña de historial: sin commits, esa
  // pantalla enseña «todavía no hay versiones», que no es lo que documenta.
  clone.log['$unitPath/es.tex'] = [
    FileCommit(
      sha: '9f2c1ab5d0',
      author: 'Javier Falcó',
      email: 'javier@uv.es',
      when: DateTime(2026, 3, 14, 9, 20),
      subject: 'Añadir el ejemplo de la norma del supremo',
    ),
    FileCommit(
      sha: '4d80e7318c',
      author: 'Javier Falcó',
      email: 'javier@uv.es',
      when: DateTime(2025, 11, 2, 18, 5),
      subject: 'Separar la definición del primer ejemplo',
    ),
    FileCommit(
      sha: '1a55c0e94b',
      author: 'Migración',
      email: 'migracion@uv.es',
      when: DateTime(2025, 9, 1, 12, 0),
      subject: 'Importar del sistema anterior',
    ),
  ];
  clone.contents['9f2c1ab5d0'] = 'El contenido original en castellano.';

  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: FakeCompiler(),
    cloneOverride: clone,
  );
  // `primeForTest` está marcado para tests y esto es una herramienta, pero es
  // exactamente el mismo uso: levantar una sesión con un catálogo de mentira
  // sin tocar el disco. La alternativa --mover esto a `test/`-- lo metería en
  // cada `flutter test`, y generar dieciséis PNG no es un test.
  // ignore: invalid_use_of_visible_for_testing_member
  await session.primeForTest(catalogue);
  return session;
}

Future<void> mount(WidgetTester tester, Session session) async {
  tester.view.physicalSize = Size(
    window.width * density,
    window.height * density,
  );
  tester.view.devicePixelRatio = density;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<UpdateService>.value(value: offlineUpdates()),
          // Apagado, que es como se abre Didacta: encenderlo es una decisión
          // de la persona. La captura del servidor enseña, por tanto, lo que
          // ve quien entra a mirar qué es esto.
          ChangeNotifierProvider<McpService>.value(
            value: McpService(
              openRunner: () =>
                  const UnavailableRunner('Aquí no hay servidor que encender.'),
            ),
          ),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: shotTheme(),
          routerConfig: buildRouter(session),
        ),
      ),
    ),
  );
  await settle(tester);
}

// ------------------------------------------------------------------ lista ---

/// Qué pantallas se capturan, en el orden en que la documentación las cuenta.
final List<Shot> shots = [
  const Shot('biblioteca', '/', note: 'la biblioteca, en árbol'),
  Shot(
    'biblioteca-buscar',
    '/',
    note: 'la biblioteca, buscando',
    prepare: (tester) async {
      final field = find.byType(TextField);
      if (field.evaluate().isEmpty) return;
      await tester.enterText(field.first, 'norm');
      await settle(tester);
    },
  ),
  Shot('unidad', '/unit/$unitPath', note: 'una unidad y su editor'),
  Shot(
    'historial',
    '/unit/$unitPath',
    note: 'el historial de un fichero',
    prepare: (tester) async {
      final tab = find.text('historial');
      if (tab.evaluate().isEmpty) return;
      await tester.tap(tab.first);
      await settle(tester);
    },
  ),
  const Shot('asignaturas', '/courses', note: 'las asignaturas'),
  const Shot('curso', '/courses/am-iii/2025-2026', note: 'un curso académico'),
  const Shot(
    'composicion',
    '/courses/am-iii/2025-2026/tema-1',
    note: 'la composición de un documento',
  ),
  Shot(
    'traduccion',
    '/translations',
    note: 'lo que falta por traducir',
    // En valenciano, que es donde el material de prueba tiene huecos. En
    // castellano --el idioma de referencia-- la pantalla dice «nada
    // pendiente», que es verdad y no documenta nada.
    prepare: (tester) async {
      final other = find.text('va');
      if (other.evaluate().isEmpty) return;
      await tester.tap(other.first);
      await settle(tester);
    },
  ),
  const Shot('ajustes', '/settings', note: 'los ajustes'),
  const Shot('mcp', '/mcp', note: 'el servidor MCP'),
];

void main() {
  setUpAll(() async {
    await loadFonts();
    // Los dibujos de la bienvenida los pinta un `CustomPainter`, que no
    // hereda el estilo de texto de nadie: sin decírselo, sus etiquetas salen
    // como rectángulos negros justo en la primera pantalla que ve alguien.
    welcomeArtFontFamily = shotFamily;
  });

  testWidgets('las capturas de las pantallas', (tester) async {
    stdout.writeln(
      'capturas a $outputDir, '
      '${window.width.toInt()}×${window.height.toInt()}:',
    );

    for (final shot in shots) {
      // Una sesión por captura: las pantallas dejan estado --una pestaña
      // abierta, un filtro escrito-- y una captura que hereda el de la
      // anterior documenta una combinación que nadie ha visto nunca.
      stdout.writeln('· ${shot.name}: sesión');
      final session = await buildSession();
      stdout.writeln('· ${shot.name}: montar');
      await mount(tester, session);
      stdout.writeln('· ${shot.name}: ir');
      routerFor(tester).go(shot.route);
      await settle(tester);
      stdout.writeln('· ${shot.name}: preparar');
      await shot.prepare?.call(tester);
      stdout.writeln('· ${shot.name}: capturar');
      await capture(tester, shot.name);
    }
  });

  testWidgets('la pantalla de bienvenida', (tester) async {
    // Aparte del resto porque no está dentro del router: es lo que se enseña
    // **en lugar de** la aplicación la primera vez, y montarla con el carril
    // detrás sería documentar algo que no ocurre.
    final session = await buildSession();
    tester.view.physicalSize = Size(
      window.width * density,
      window.height * density,
    );
    tester.view.devicePixelRatio = density;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: shotTheme(),
            home: WelcomeScreen(session: session),
          ),
        ),
      ),
    );
    await settle(tester);
    await capture(tester, 'bienvenida');

    // Y el paso del asistente donde se abre el primer repositorio, que es lo
    // que hay que enseñar en «el primer repositorio».
    final next = find.text('Empezar');
    if (next.evaluate().isNotEmpty) {
      await tester.tap(next.first);
      await settle(tester);
      await capture(tester, 'bienvenida-repositorio');
    }
  });
}

/// El router de la aplicación montada, para poder navegar.
GoRouterLike routerFor(WidgetTester tester) => GoRouterLike(tester);

/// Un envoltorio mínimo para no importar go_router aquí.
///
/// Navegar en una captura es ir a una dirección, y `Session` ya no expone
/// eso; lo hace el router. Buscar el `BuildContext` de la aplicación y llamar
/// a `goTo` --que es la función que el resto de la aplicación usa-- evita que
/// esta herramienta dependa de cómo está implementado el enrutado.
class GoRouterLike {
  const GoRouterLike(this.tester);

  final WidgetTester tester;

  void go(String route) {
    final context = tester.element(find.byType(Navigator).first);
    goTo(context, route);
  }
}
