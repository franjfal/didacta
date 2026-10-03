/// Capturas de la biblioteca en tres niveles, para mirarla sin abrir la
/// aplicación: las columnas, una ventana mediana y los diálogos de crear un
/// subtema, crear una lección y moverla, en claro y en oscuro.
///
///     cd app && DIDACTA_SHOTS_OUT=/tmp/x flutter test tool/shots_library.dart
///
/// Sin `DIDACTA_SHOTS_OUT` escribe donde las demás, en `web/docs/img/app/`.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/course_admin.dart';
import 'package:didacta_app/l10n/tr.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/ui/welcome_art.dart';

import '../test/fixture.dart';
import 'generate_screenshots.dart';
import 'screenshot_material.dart';

Future<FakeSession> _session() async {
  final catalogue = screenshotCatalogue();
  final engine = FakeCompiler();
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: engine,
    adminOverride: CourseAdmin(
      compiler: engine,
      clone: FakeClone(changed: true),
      author: (name: 'Javier', email: 'javier@uv.es'),
      token: '',
      pushOnCommit: false,
    ),
  );
  // Uno en el que se puede escribir, para que salgan los botones de crear.
  session.repositories.workspace = Workspace([
    ContentRepo(owner: 'franjfal', name: 'didacta_db', directory: '/tmp/x'),
  ]);
  // ignore: invalid_use_of_visible_for_testing_member
  await session.primeForTest(catalogue);
  return session;
}

void main() {
  setUpAll(() async {
    await loadFonts();
    welcomeArtFontFamily = shotFamily;
    useUiLanguage(shotLanguage);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'oscuro' : 'claro';

    testWidgets('la biblioteca en columnas, en $mode', (tester) async {
      stdout.writeln('capturas a $outputDir ($mode):');
      Future<void> at(String route, String name) async {
        final session = await _session();
        await mount(tester, session, dark: dark);
        routerFor(tester).go(route);
        await settle(tester);
        await capture(tester, 'biblioteca3-$name-$mode');
      }

      await at('/?en=analysis', 'categoria');
      await at('/?en=analysis/normed', 'tema');
      await at('/?en=analysis/normed/fundamentos', 'subtema');
    });

    testWidgets('los diálogos, en $mode', (tester) async {
      Future<FakeSession> open() async {
        final session = await _session();
        await mount(tester, session, dark: dark);
        routerFor(tester).go('/?en=analysis/normed/fundamentos');
        await settle(tester);
        return session;
      }

      // Crear un subtema, al pie de su columna.
      await open();
      await tester.tap(find.byKey(const Key('library-add-2')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('place-name-es')),
        'Espacios de Hilbert',
      );
      await settle(tester);
      await capture(tester, 'biblioteca3-nuevo-subtema-$mode');

      // Una lección nueva: las columnas abiertas donde se estaba.
      await open();
      await tester.tap(find.byKey(const Key('library-new-unit')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('new-unit-title')),
        'El teorema de Riesz',
      );
      await settle(tester);
      await capture(tester, 'biblioteca3-nueva-leccion-$mode');

      // Mover: el botón derecho sobre una tarjeta, «Mover a…».
      await open();
      final card = find.text('Espacios normados').last;
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await settle(tester);
      await capture(tester, 'biblioteca3-menu-$mode');
      await tester.tap(find.byKey(const Key('unit-card-move')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('place-series')).first);
      await settle(tester);
      await capture(tester, 'biblioteca3-mover-$mode');
    });
  }

  testWidgets('una ventana mediana', (tester) async {
    final session = await _session();
    await mount(tester, session);
    tester.view.physicalSize = Size(960 * density, 820 * density);
    await settle(tester);
    routerFor(tester).go('/?en=analysis/normed/fundamentos');
    await settle(tester);
    await capture(tester, 'biblioteca3-mediana-claro');
  });
}
