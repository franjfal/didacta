/// Ojear una lección compilada desde la biblioteca.
///
/// La pregunta que resuelve es la de quien prepara una clase: de estas ocho
/// lecciones sobre sucesiones, ¿cuál era la que tenía el dibujo? Entrar en
/// cada una, mirar y volver son tres pasos por lección.
///
/// Lo que estos tests sujetan es qué se ofrece y qué se abre --el PDF que
/// toca, o el que hay diciéndolo-- y que no aparezca un botón que no lleva a
/// ningún sitio, que es lo que haría dudar de todos los demás.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/quick_look.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const String definition = 'content/analysis/normed/definition';

ExistingOutput output({
  String profile = 'slides',
  String language = 'es',
  bool stale = false,
}) => ExistingOutput(
  profile: profile,
  label: profile == 'slides' ? 'Diapositivas' : 'Libro',
  family: profile == 'slides' ? 'slides' : 'notes',
  language: language,
  pdf: '/salida/$profile-$language.pdf',
  exists: true,
  stale: stale,
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeSession> pumpLibrary(
  WidgetTester tester, {
  Map<String, List<ExistingOutput>> built = const {},
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final compiler = FakeCompiler()..built = built;
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: compiler,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: LibraryPage()),
      ),
    ),
  );
  await settle(tester);
  return session;
}

void main() {
  group('qué se puede ojear', () {
    test('sin nada compilado, nada', () async {
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );
      await session.primeForTest(catalogueWith(defaultUnits()));
      final unit = session.catalogue.units.first;
      expect(quickLookFor(session, unit), isNull);
    });

    test('la versión elegida y el idioma que se mira, si está', () async {
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );
      await session.primeForTest(catalogueWith(defaultUnits()));
      await session.setBuiltForTest({
        definition: [
          output(profile: 'book', language: 'es'),
          output(profile: 'slides', language: 'va'),
          output(profile: 'slides', language: 'es'),
        ],
      });

      final unit = session.catalogue.units.firstWhere(
        (u) => u.path == definition,
      );
      final found = quickLookFor(session, unit)!;
      expect(found.profile, 'slides', reason: 'la elegida arriba');
      expect(found.language, 'es', reason: 'el idioma que se está mirando');
    });

    test('si la elegida no está, otra, pero se dice cuál', () async {
      // Enseñar diapositivas cuando se pidió libro es mejor que no enseñar
      // nada, pero solo si se dice; lo segundo lo comprueba el modal.
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      );
      await session.primeForTest(catalogueWith(defaultUnits()));
      await session.setPreviewProfile('book');
      await session.setBuiltForTest({
        definition: [output(profile: 'slides', language: 'va')],
      });

      final unit = session.catalogue.units.firstWhere(
        (u) => u.path == definition,
      );
      expect(quickLookFor(session, unit)!.profile, 'slides');
    });
  });

  group('en la biblioteca', () {
    testWidgets('se pregunta una sola vez qué hay compilado', (tester) async {
      // Dos mil unidades y una llamada: preguntarlo por tarjeta serían dos
      // mil procesos para pintar una lista.
      final session = await pumpLibrary(tester);
      final compiler = session.compiler()! as FakeCompiler;
      expect(compiler.builtCalls, 1);
    });

    testWidgets('sin nada compilado no hay botón de ojear', (tester) async {
      await pumpLibrary(tester);
      await tester.enterText(find.byType(TextField).first, 'normados');
      await settle(tester);
      expect(find.byKey(const Key('quick-look-$definition')), findsNothing);
    });

    testWidgets('con algo compilado, el botón está', (tester) async {
      await pumpLibrary(
        tester,
        built: {
          definition: [output()],
        },
      );
      await tester.enterText(find.byType(TextField).first, 'normados');
      await settle(tester);
      expect(find.byKey(const Key('quick-look-$definition')), findsOneWidget);
    });

    testWidgets('el desplegable elige qué versión se abre', (tester) async {
      final session = await pumpLibrary(
        tester,
        built: {
          definition: [output()],
        },
      );
      expect(session.previewProfile, 'slides');

      await tester.tap(find.byKey(const Key('preview-picker')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('preview-book')));
      await settle(tester);

      expect(session.previewProfile, 'book');
      // Y se recuerda, que si no hay que elegirlo en cada arranque.
      expect(await session.preferences.previewProfile(), 'book');
    });
  });
}
