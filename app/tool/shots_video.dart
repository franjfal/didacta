/// Las capturas de los videotutoriales, pintadas por la propia aplicación.
///
///     cd app && DIDACTA_VIDEO=A01-didacta-en-dos-minutos \
///         flutter test tool/shots_video.dart
///
/// Normalmente no se llama a mano: lo hace `videos/hacer.py`, que es quien
/// sabe en qué orden van las cosas.
///
/// Lee `videos/<vídeo>/capturas.json` --qué pantallas, qué se pulsa en cada
/// una y qué zonas le interesan al montaje-- y escribe en
/// `videos/.build/<vídeo>/capturas/` un PNG por pantalla y, al lado, un JSON
/// con **dónde está cada zona** en esa imagen.
///
/// Lo segundo es lo que hace que un vídeo se pueda rehacer. El montaje no
/// dice «acércate a (1830, 244)»: dice «acércate a la pestaña de compilar», y
/// la pestaña está donde esté en la versión de ahora. Si mañana se mueve, se
/// vuelven a sacar las capturas y la cámara la sigue sola.
///
/// Por qué con una sesión de verdad y no con la de mentira de
/// `generate_screenshots.dart`: aquel material es a propósito incómodo --una
/// referencia rota, una traducción vieja-- porque documenta los casos raros.
/// Un vídeo enseña el caso de todos los días, y además lo enseña **con el
/// repositorio de ejemplo**, el mismo que tiene quien lo mira. Así que esto
/// copia `assets/ejemplo` a una carpeta temporal, le pone git y un remoto, y
/// abre Didacta encima como la abriría cualquiera: con el motor de verdad, el
/// índice de verdad y la barra de abajo diciendo «al día».
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/github.dart';
import 'package:didacta_app/data/mcp_process.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/data/toolchain.dart';
import 'package:didacta_app/l10n/tr.dart';
import 'package:didacta_app/model/toolchain.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/router.dart';
import 'package:didacta_app/state/appearance.dart';
import 'package:didacta_app/state/mcp_service.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/state/update_service.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/sign_in.dart';
import 'package:didacta_app/ui/tour.dart';
import 'package:didacta_app/ui/welcome.dart';
import 'package:didacta_app/ui/welcome_art.dart';

import '../test/fixture.dart';
import 'generate_screenshots.dart'
    show loadFonts, routerFor, shotFamily, shotTheme;

/// La ventana, en puntos: la de un portátil, y la misma para todos los vídeos.
/// Una captura a otro tamaño parece de otra aplicación.
const Size window = Size(1440, 900);

/// Retina: la nitidez se pide aquí, no al capturar (ver
/// `generate_screenshots.dart`). A 2880×1800 la cámara del vídeo puede
/// acercarse al doble sin que se vean los píxeles.
const double density = 2.0;

/// Como se llama el repositorio de ejemplo cuando lo crea la aplicación.
const String owner = 'profe';
const String repoName = 'didacta-ejemplo';
const String repoId = '$owner/$repoName';

final GlobalKey _frame = GlobalKey();

String engineRoot() {
  var directory = Directory.current;
  for (var i = 0; i < 4; i += 1) {
    if (File('${directory.path}/cli/didacta').existsSync()) {
      return directory.path;
    }
    directory = directory.parent;
  }
  throw StateError(
    'No encuentro la raíz de Didacta desde ${Directory.current}',
  );
}

void main() {
  final video = Platform.environment['DIDACTA_VIDEO'];
  final engine = engineRoot();
  // Dónde dice la aplicación que está el motor. Por defecto este clon, que
  // en un vídeo enseñaría la carpeta de quien lo graba; `hacer.py` da un
  // enlace con un nombre neutro.
  final shownEngine = Platform.environment['DIDACTA_MOTOR_VIDEO'] ?? engine;

  late Directory root;
  late String work;
  late String out;
  late Map<String, dynamic> spec;

  Future<void> run(String exe, List<String> args, String where) async {
    final result = await Process.run(exe, args, workingDirectory: where);
    if (result.exitCode != 0) {
      throw StateError(
        '$exe ${args.join(' ')}\n${result.stdout}${result.stderr}',
      );
    }
  }

  setUpAll(() async {
    if (video == null) return;
    await loadFonts();
    // El visor de PDF pide una carpeta temporal a `path_provider`, que en una
    // prueba no existe: la de esta ejecución, como en los tests del visor.
    final cache = Directory.systemTemp.createTempSync('didacta-pdfrx-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => cache.path,
        );
    // Los dibujos de la bienvenida son un `CustomPainter` y no heredan la
    // tipografía: sin esto, sus etiquetas salen como rectángulos negros.
    welcomeArtFontFamily = shotFamily;
    useUiLanguage(UiLanguage.es);

    spec =
        jsonDecode(
              File('$engine/videos/$video/capturas.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    out = '$engine/videos/.build/$video/capturas';
    Directory(out).createSync(recursive: true);

    // El repositorio de ejemplo, como lo dejaría «Probar con un ejemplo»: una
    // copia con su historial y un remoto que se llama como él --si no se
    // llama igual, la sesión no lo reconoce como suyo--.
    root = Directory.systemTemp.createTempSync('didacta-video-');
    work = '${root.path}/$owner/$repoName';
    Directory('${root.path}/$owner').createSync(recursive: true);
    await run('cp', ['-R', '$engine/app/assets/ejemplo', work], root.path);
    final remote = '${root.path}/$owner/$repoName.git';
    await run('git', [
      'init',
      '--bare',
      '--initial-branch=main',
      remote,
    ], root.path);
    await run('$engine/cli/didacta', ['index'], work);
    await run('git', ['init', '--initial-branch=main'], work);
    await run('git', ['add', '.'], work);
    await run('git', [
      '-c',
      'user.name=Didacta',
      '-c',
      'user.email=didacta@example.org',
      'commit',
      '-m',
      'El repositorio de ejemplo',
    ], work);
    await run('git', ['remote', 'add', 'origin', remote], work);
    await run('git', ['push', '-u', 'origin', 'main'], work);
  });

  tearDownAll(() async {
    if (video == null) return;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Deja el repositorio como lo pide la captura antes de abrirlo:
  /// `"preparar": [{"en_github": 1}, {"sin_enviar": 2}]` son cambios que otra
  /// máquina ya envió a GitHub, y cambios guardados aquí sin enviar. Lo que se
  /// prepara se queda para las capturas siguientes del mismo vídeo.
  Future<void> prepare(Map<String, dynamic> shot) async {
    Future<void> commit(String where, String message) => run('git', [
      '-c',
      'user.name=Otra máquina',
      '-c',
      'user.email=profe@uv.es',
      'commit',
      '--allow-empty',
      '-m',
      message,
    ], where);
    for (final raw in (shot['preparar'] as List?) ?? const []) {
      final step = (raw as Map).cast<String, dynamic>();
      if (step['en_github'] case final num n) {
        final other = Directory.systemTemp.createTempSync('didacta-otra-');
        await run('git', [
          'clone',
          '-q',
          '${root.path}/$owner/$repoName.git',
          other.path,
        ], root.path);
        for (var i = 0; i < n; i += 1) {
          await commit(other.path, 'Un cambio desde el despacho');
        }
        await run('git', ['push', '-q', 'origin', 'main'], other.path);
        await run('git', ['fetch', '-q', 'origin'], work);
        other.deleteSync(recursive: true);
      }
      if (step['sin_enviar'] case final num n) {
        for (var i = 0; i < n; i += 1) {
          await commit(work, 'Corregir una errata');
        }
      }
    }
  }

  /// La sesión de una captura. `sin_sesion`: sin haber entrado en GitHub;
  /// `sin_repositorios`: sin ningún repositorio abierto, como la primera vez.
  Future<Session> openSession([Map<String, dynamic> shot = const {}]) async {
    final source = CatalogueSource.inClone(work, repo: repoId)!;
    final session = VideoSession(
      missing: {
        for (final name in (shot['falta'] as List?) ?? const [])
          ToolId.values.byName(name as String),
      },
      catalogueSource: source,
      tokenStore: shot['sin_sesion'] == true
          ? StubStore(token: null)
          : StubStore(),
      // Con el Client ID de la aplicación, como la de verdad: sin él, la
      // bienvenida pide uno, que es lo que no ve nunca quien la instala.
      preferences: MemoryPreferences(
        engine: shownEngine,
        clientId: didactaAppClientId.isEmpty
            ? 'Iv23liDidacta'
            : didactaAppClientId,
      ),
    );
    session.repositories.workspace = Workspace([
      if (shot['sin_repositorios'] != true)
        ContentRepo(owner: owner, name: repoName, directory: work),
    ]);
    await session.findEngine();
    // Marcado para tests, y esto es una herramienta: el mismo uso que en
    // `shots_reuse.dart` --levantar una sesión sobre un repositorio concreto
    // sin pasar por Ajustes--.
    // ignore: invalid_use_of_visible_for_testing_member
    await session.primeForTest(await source.load());
    await session.setCloneAuthor(name: 'Profe de Prueba', email: 'profe@uv.es');
    // Los ajustes no se leen de las preferencias en una sesión así: el Client
    // ID de la aplicación, dicho a mano.
    await session.setGithubClientId(didactaAppClientId);
    return session;
  }

  /// La aplicación montada con su router o, con [welcome], la bienvenida:
  /// lo que se ve **en lugar de** la aplicación al abrirla por primera vez.
  Future<void> mount(
    WidgetTester tester,
    Session session, {
    bool welcome = false,
  }) async {
    tester.view.physicalSize = Size(
      window.width * density,
      window.height * density,
    );
    tester.view.devicePixelRatio = density;
    addTearDown(tester.view.reset);
    final appearance = Appearance();
    await tester.runAsync(() => appearance.setMode(AppearanceMode.light));
    // El recorrido guiado, como lo monta `main.dart`: enganchado al router
    // para poder cambiar de pantalla, y su capa por encima de la aplicación.
    final tour = TourController();
    final router = buildRouter(session);
    tour.attach(
      navigate: router.go,
      locate: () => router.routeInformationProvider.value.uri.toString(),
      session: session,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        // Una clave nueva cada vez: si no, Flutter reaprovecha el estado de
        // la captura anterior --la bienvenida seguía en el paso donde se
        // quedó--.
        child: KeyedSubtree(
          key: UniqueKey(),
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<Session>.value(value: session),
              ChangeNotifierProvider<UpdateService>.value(
                value: offlineUpdates(),
              ),
              ChangeNotifierProvider<Appearance>.value(value: appearance),
              ChangeNotifierProvider<TourController>.value(value: tour),
              ChangeNotifierProvider<McpService>.value(
                value: McpService(
                  openRunner: () =>
                      const UnavailableRunner('Sin servidor en un vídeo.'),
                ),
              ),
            ],
            child: welcome
                ? MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: shotTheme(DidactaPalette.light),
                    home: WelcomeScreen(session: session),
                  )
                : ListenableBuilder(
                    listenable: appearance,
                    builder: (context, _) => MaterialApp.router(
                      debugShowCheckedModeBanner: false,
                      theme: shotTheme(
                        appearance.brightness == Brightness.dark
                            ? DidactaPalette.dark
                            : DidactaPalette.light,
                      ),
                      routerConfig: router,
                      builder: (context, child) => Stack(
                        children: [
                          child ?? const SizedBox.shrink(),
                          TourOverlay(controller: tour),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// Deja que lo que va al disco termine. Con el reloj de una prueba no
  /// avanza una lectura de fichero, así que se alterna tiempo de verdad y
  /// fotogramas (ver `didacta-verificar-pantallas-con-capturas`).
  Future<void> settleReal(WidgetTester tester, {int rounds = 8}) async {
    for (var round = 0; round < rounds; round += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> capture(WidgetTester tester, String path) async {
    final boundary =
        _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes;
    });
    if (png == null) throw StateError('no se pudo codificar $path');
    File(path).writeAsBytesSync(png.buffer.asUint8List(), flush: true);
  }

  // ------------------------------------------------------------- zonas ---

  Finder? finderFor(Map<String, dynamic> what) {
    if (what['texto'] case final String text) return find.text(text);
    if (what['contiene'] case final String text) {
      return find.textContaining(text);
    }
    if (what['consejo'] case final String tip) return find.byTooltip(tip);
    if (what['clave'] case final String key) return find.byKey(Key(key));
    return null;
  }

  /// Un trozo del texto del editor --de `from` hasta `to`, incluido--.
  Rect? editorZone(WidgetTester tester, String from, String? to) {
    final editors = find.byType(EditableText).evaluate().toList();
    if (editors.isEmpty) return null;
    // El editor de la lección es el más grande: puede haber otros campos.
    editors.sort((a, b) {
      final ra = (a.renderObject! as RenderBox).size;
      final rb = (b.renderObject! as RenderBox).size;
      return (rb.width * rb.height).compareTo(ra.width * ra.height);
    });
    final state = (editors.first as StatefulElement).state as EditableTextState;
    final text = state.textEditingValue.text;
    final start = text.indexOf(from);
    if (start < 0) return null;
    var end = start + from.length;
    if (to != null) {
      final found = text.indexOf(to, start);
      if (found >= 0) end = found + to.length;
    }
    final editable = state.renderEditable;
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    if (boxes.isEmpty) return null;
    var rect = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      rect = rect.expandToInclude(box.toRect());
    }
    final origin = editable.localToGlobal(Offset.zero);
    return rect.shift(origin);
  }

  /// La zona de lo que se busca, en píxeles de la imagen.
  ///
  /// `fila` sube desde el texto hasta el primer antepasado que mide al menos
  /// `ancho` puntos: la fila entera de una lista, que es lo que se señala,
  /// sin tener que saber de qué widget está hecha.
  Rect? zone(WidgetTester tester, Map<String, dynamic> what) {
    if (what['editor'] case final String from) {
      return editorZone(tester, from, what['hasta'] as String?);
    }
    final finder = finderFor(what);
    if (finder == null || finder.evaluate().isEmpty) return null;
    final index = (what['n'] as num?)?.toInt() ?? 0;
    final elements = finder.evaluate().toList();
    if (index >= elements.length) return null;
    final element = elements[index];
    var rect = tester.getRect(find.byElementPredicate((e) => e == element));
    // `fila`: la zona crece hasta lo primero que la contiene con al menos ese
    // ancho (la fila entera de una lista); `alto`, con al menos ese alto (la
    // tarjeta entera de un título).
    final minWidth = (what['fila'] as num?)?.toDouble();
    final minHeight = (what['alto'] as num?)?.toDouble();
    if (minWidth != null || minHeight != null) {
      element.visitAncestorElements((ancestor) {
        final box = ancestor.renderObject;
        if (box is RenderBox && box.hasSize) {
          final r = box.localToGlobal(Offset.zero) & box.size;
          if (r.width >= (minWidth ?? 0) && r.height >= (minHeight ?? 0)) {
            rect = r;
            return false;
          }
        }
        return true;
      });
    }
    return rect;
  }

  Map<String, List<double>> zones(
    WidgetTester tester,
    Map<String, dynamic>? wanted,
  ) {
    final result = <String, List<double>>{};
    for (final entry in (wanted ?? const {}).entries) {
      final rect = zone(tester, (entry.value as Map).cast<String, dynamic>());
      if (rect == null) {
        stdout.writeln('    (sin zona «${entry.key}»: no está en la pantalla)');
        continue;
      }
      result[entry.key] = [
        for (final v in [rect.left, rect.top, rect.width, rect.height])
          (v * density).roundToDouble(),
      ];
    }
    return result;
  }

  void writeZones(String path, Map<String, List<double>> found) {
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'ancho': window.width * density,
        'alto': window.height * density,
        'densidad': density,
        'zonas': found,
      }),
    );
  }

  // ---------------------------------------------------------- acciones ---

  /// Desplaza el editor hasta que `hasta` quede arriba, a `margen` puntos.
  ///
  /// Con `fotogramas`, guarda el desplazamiento entero a 30 por segundo: es
  /// el editor de verdad moviéndose, no una imagen alta que se desliza.
  Future<void> scrollEditor(
    WidgetTester tester,
    Map<String, dynamic> what,
    Map<String, dynamic> shot,
  ) async {
    final editors = find.byType(EditableText).evaluate().toList()
      ..sort((a, b) {
        final ra = (a.renderObject! as RenderBox).size;
        final rb = (b.renderObject! as RenderBox).size;
        return (rb.width * rb.height).compareTo(ra.width * ra.height);
      });
    if (editors.isEmpty) return;
    final element = editors.first as StatefulElement;
    final state = element.state as EditableTextState;
    final index = state.textEditingValue.text.indexOf(what['hasta'] as String);
    // El desplazamiento del editor es suyo: el `Scrollable` que `EditableText`
    // lleva dentro, no uno de fuera.
    final inner = find.descendant(
      of: find.byElementPredicate((e) => e == element),
      matching: find.byType(Scrollable),
    );
    final ScrollableState? scrollable = inner.evaluate().isEmpty
        ? Scrollable.maybeOf(element)
        : tester.state<ScrollableState>(inner.first);
    if (index < 0 || scrollable == null) {
      stdout.writeln('    (no puedo desplazar hasta «${what['hasta']}»)');
      return;
    }
    final editable = state.renderEditable;
    final caret = editable.getLocalRectForCaret(TextPosition(offset: index));
    final y = editable.localToGlobal(caret.topLeft).dy;
    final viewport = scrollable.context.findRenderObject()! as RenderBox;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final position = scrollable.position;
    final start = position.pixels;
    final margin = (what['margen'] as num?)?.toDouble() ?? 24;
    final target = (start + y - top - margin).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final frames = (what['fotogramas'] as num?)?.toInt() ?? 0;
    if (frames <= 0) {
      position.jumpTo(target);
      await settleReal(tester, rounds: 2);
      return;
    }
    final name = what['nombre'] as String? ?? '${shot['nombre']}-desplazar';
    for (var i = 0; i <= frames; i += 1) {
      final t = i / frames;
      final eased = t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
      position.jumpTo(start + (target - start) * eased);
      await tester.pump(const Duration(microseconds: 33333));
      await capture(tester, '$out/$name-${i.toString().padLeft(3, '0')}.png');
    }
    stdout.writeln('    ${frames + 1} fotogramas de «$name»');
  }

  /// Arrastra una fila de una lista reordenable y guarda cada fotograma.
  ///
  /// No es una simulación del arrastre: es la lista de verdad, con su
  /// animación de verdad, fotografiada a 30 fotogramas por segundo.
  Future<void> dragFrames(
    WidgetTester tester,
    Map<String, dynamic> drag,
    Map<String, dynamic> shot,
  ) async {
    final row = find.text(drag['fila'] as String);
    if (row.evaluate().isEmpty) {
      stdout.writeln('    (no encuentro la fila «${drag['fila']}»)');
      return;
    }
    final rowCenter = tester.getCenter(row.first);
    // El asa de la misma fila: la que está a su altura.
    final handles = find.byIcon(Icons.drag_indicator).evaluate().toList();
    if (handles.isEmpty) return;
    Offset? handle;
    for (final element in handles) {
      final c = tester.getCenter(find.byElementPredicate((e) => e == element));
      if (handle == null ||
          (c.dy - rowCenter.dy).abs() < (handle.dy - rowCenter.dy).abs()) {
        handle = c;
      }
    }
    final name = drag['nombre'] as String? ?? '${shot['nombre']}-arrastre';
    final dy = (drag['dy'] as num).toDouble();
    final moving = (drag['fotogramas'] as num?)?.toInt() ?? 24;
    final hold = (drag['quieto'] as num?)?.toInt() ?? 8;
    final after = (drag['despues'] as num?)?.toInt() ?? 12;
    const step = Duration(microseconds: 33333);

    var frame = 0;
    // `guardar: false` arrastra sin fotografiar: para cuando lo que interesa
    // es el estado de después, que queda en la captura final.
    final keep = drag['guardar'] != false;
    Future<void> shootFrame() async {
      if (keep) {
        await capture(
          tester,
          '$out/$name-${frame.toString().padLeft(3, '0')}.png',
        );
      }
      frame += 1;
    }

    final gesture = await tester.startGesture(handle!);
    await tester.pump(step);
    await shootFrame();
    var moved = 0.0;
    for (var i = 1; i <= moving; i += 1) {
      // Con aceleración y frenada, como una mano.
      final t = i / moving;
      final eased = t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
      final target = dy * eased;
      await gesture.moveBy(Offset(0, target - moved));
      moved = target;
      await tester.pump(step);
      await shootFrame();
    }
    for (var i = 0; i < hold; i += 1) {
      await tester.pump(step);
      await shootFrame();
    }
    await gesture.up();
    for (var i = 0; i < after; i += 1) {
      await tester.pump(step);
      await shootFrame();
    }
    stdout.writeln('    $frame fotogramas de «$name»');
  }

  LogicalKeyboardKey keyFor(String name) => switch (name.toLowerCase()) {
    'meta' || 'cmd' => LogicalKeyboardKey.meta,
    'control' || 'ctrl' => LogicalKeyboardKey.control,
    'shift' => LogicalKeyboardKey.shift,
    'alt' => LogicalKeyboardKey.alt,
    'escape' || 'esc' => LogicalKeyboardKey.escape,
    'enter' => LogicalKeyboardKey.enter,
    'tab' => LogicalKeyboardKey.tab,
    'slash' || '/' => LogicalKeyboardKey.slash,
    _ => LogicalKeyboardKey(
      LogicalKeyboardKey.keyA.keyId + name.codeUnitAt(0) - 'a'.codeUnitAt(0),
    ),
  };

  /// GitHub, sin preguntarle: da un código de ejemplo y deniega la espera
  /// en cuanto el reloj de la prueba llega al primer sondeo.
  GitHubAuth fakeGitHub(String clientId) => GitHubAuth(
    clientId: clientId,
    client: MockClient((request) async {
      if (request.url.path.contains('device/code')) {
        return http.Response(
          jsonEncode({
            'device_code': 'video',
            'user_code': 'WDJB-MJHT',
            'verification_uri': 'https://github.com/login/device',
            'expires_in': 900,
            'interval': 5,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'error': 'access_denied'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  Future<void> act(
    WidgetTester tester,
    Session session,
    Map<String, dynamic> action,
    Map<String, dynamic> shot,
  ) async {
    if (action['pulsar'] case final Map what) {
      final finder = finderFor(what.cast<String, dynamic>());
      if (finder == null || finder.evaluate().isEmpty) {
        stdout.writeln('    (no encuentro qué pulsar: $what)');
        return;
      }
      await tester.tap(finder.first);
      await settleReal(
        tester,
        rounds: (action['esperar'] as num?)?.toInt() ?? 10,
      );
    } else if (action['lado_a_lado'] == true) {
      await tester.runAsync(() => session.setSplitEditors(true));
      await settleReal(tester, rounds: 12);
    } else if (action['arrastrar'] case final Map drag) {
      await dragFrames(tester, drag.cast<String, dynamic>(), shot);
    } else if (action['desplazar_editor'] case final Map what) {
      await scrollEditor(tester, what.cast<String, dynamic>(), shot);
    } else if (action['capturar'] case final Map what) {
      // Una foto a mitad de camino: el estado antes de arrastrar, por ejemplo.
      final name = what['nombre'] as String;
      await capture(tester, '$out/$name.png');
      writeZones(
        '$out/$name.json',
        zones(tester, (what['cajas'] as Map?)?.cast<String, dynamic>()),
      );
      stdout.writeln('  $name.png');
    } else if (action['esperar'] case final num rounds) {
      await settleReal(tester, rounds: rounds.toInt());
    } else if (action['escribir'] case final Map what) {
      // Escribir en un campo: `{"en": {"clave": ...}, "texto": "..."}`.
      final finder = finderFor((what['en'] as Map).cast<String, dynamic>());
      if (finder == null || finder.evaluate().isEmpty) {
        stdout.writeln('    (no encuentro dónde escribir: $what)');
        return;
      }
      await tester.enterText(finder.first, what['texto'] as String);
      await settleReal(tester, rounds: (what['esperar'] as num?)?.toInt() ?? 8);
    } else if (action['tecla'] case final String combo) {
      // Un atajo: «meta+k», «control+f», «escape».
      final keys = combo.split('+').map(keyFor).toList();
      for (final key in keys) {
        await tester.sendKeyDownEvent(key);
      }
      for (final key in keys.reversed) {
        await tester.sendKeyUpEvent(key);
      }
      await settleReal(tester, rounds: 8);
    } else if (action['avanzar'] case final num seconds) {
      // El reloj de la prueba, hacia delante: lo que espera un tiempo
      // --el sondeo de GitHub, por ejemplo-- termina y no deja temporizadores.
      await tester.pump(Duration(milliseconds: (seconds * 1000).round()));
      await settleReal(tester, rounds: 4);
    }
  }

  // -------------------------------------------------------------- todo ---

  testWidgets(
    'las capturas del vídeo',
    (tester) async {
      if (video == null) {
        stdout.writeln(
          'Falta DIDACTA_VIDEO=<carpeta de videos/>; no hago nada.',
        );
        return;
      }
      stdout.writeln('capturas de $video a $out:');
      // Marcado para tests, y esto es una herramienta (como `primeForTest`).
      // ignore: invalid_use_of_visible_for_testing_member
      signInAuth = fakeGitHub;
      for (final raw in spec['capturas'] as List) {
        final shot = (raw as Map).cast<String, dynamic>();
        final name = shot['nombre'] as String;
        late Session session;
        await tester.runAsync(() => prepare(shot));
        await tester.runAsync(() async => session = await openSession(shot));
        final welcome = shot['bienvenida'] == true;
        await mount(tester, session, welcome: welcome);
        await settleReal(tester, rounds: 3);
        if (!welcome) {
          routerFor(tester).go(shot['ruta'] as String);
          await settleReal(tester);
        }

        // Las zonas se miden antes de las acciones si se piden así: la fila que
        // se va a arrastrar, por ejemplo, está en su sitio antes de moverla.
        final before = zones(
          tester,
          (shot['cajas_antes'] as Map?)?.cast<String, dynamic>(),
        );
        for (final action in (shot['acciones'] as List?) ?? const []) {
          await act(
            tester,
            session,
            (action as Map).cast<String, dynamic>(),
            shot,
          );
        }
        await capture(tester, '$out/$name.png');
        final found = {
          ...before,
          ...zones(tester, (shot['cajas'] as Map?)?.cast<String, dynamic>()),
        };
        writeZones('$out/$name.json', found);
        stdout.writeln('  $name.png  (${found.length} zonas)');
      }
      // Sin pantallas montadas antes de acabar: la barra de sincronización
      // deja temporizadores, y el arnés se queja de los que siguen vivos.
      await tester.pumpWidget(const SizedBox.shrink());
      await settleReal(tester, rounds: 3);
    },
    timeout: const Timeout(Duration(minutes: 20)),
    // Como en el Mac, que es donde se graban: los atajos dicen ⌘ y no Ctrl,
    // y un campo de texto no saca las asas de selección de un móvil.
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

/// La sesión de los vídeos: la de las pruebas, con la opción de fingir que
/// falta alguna herramienta (`"falta": ["latex"]` en la captura). Lo demás
/// es lo de esta máquina, con sus rutas de verdad.
class VideoSession extends LocalSession {
  VideoSession({
    required super.catalogueSource,
    required super.tokenStore,
    super.preferences,
    this.missing = const {},
  });

  final Set<ToolId> missing;

  @override
  Toolchain toolchain() {
    final real = super.toolchain();
    return missing.isEmpty ? real : _Missing(real, missing);
  }
}

/// Las herramientas de esta máquina, menos las que se dice que faltan: de
/// esas se enseña dónde se buscaron, que es lo que ve quien no las tiene.
class _Missing implements Toolchain {
  _Missing(this.real, this.missing);

  final Toolchain real;
  final Set<ToolId> missing;

  ToolState _hide(ToolState found) => missing.contains(found.tool.id)
      ? ToolState(tool: found.tool, searched: found.searched)
      : found;

  @override
  Host get host => real.host;

  @override
  Future<ToolState> inspect(ToolId id) async => _hide(await real.inspect(id));

  @override
  Future<List<ToolState>> inspectAll() async => [
    for (final found in await real.inspectAll()) _hide(found),
  ];

  @override
  Future<InstallPlan> choose(List<InstallPlan> candidates) =>
      real.choose(candidates);

  @override
  Future<void> install(
    InstallPlan plan, {
    void Function(String line)? onOutput,
  }) async {}
}
