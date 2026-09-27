/// Los idiomas en Ajustes: etiquetas para lo que está, un desplegable para lo
/// que falta, y una pregunta antes de quitar.
///
/// Eran diez chips marcados y sin marcar en una fila, y lo que se prueba aquí
/// es lo que cambia con la forma nueva: que solo se ven como etiqueta los que
/// están, que añadir pasa por el desplegable, que quitar **no se hace** sin
/// contestar que sí, y que los que no se pueden quitar ni siquiera ofrecen la
/// cruz.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/ui/language_settings.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const String settingsYaml = '''
name: "Pruebas"
languages: [es, va, en]
default_language: es
''';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> courseIn(List<String> languages) => {
  'id': 'am-i',
  'title': const {'es': 'Análisis Matemático I'},
  'language': 'es',
  'languages': languages,
  'years': const <String, dynamic>{},
};

/// Castellano de referencia, valenciano en uso por una asignatura e inglés
/// libre: los tres casos de una etiqueta, en un repositorio.
Future<({FakeSession session, FakeGateway gateway})> pumpLanguages(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final gateway = FakeGateway(files: {'didacta.yaml': settingsYaml});
  final catalogue = catalogueWith(
    const [],
    courses: [
      courseIn(const ['es', 'va']),
    ],
    repo: 'test/repo',
  );
  final session = FakeSession(
    gatewayOverride: gateway,
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');

  await tester.pumpWidget(
    MaterialApp(
      theme: didactaTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) => LanguageSettings(session: session),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return (session: session, gateway: gateway);
}

Finder tag(String prefix, String code) => find.byKey(Key('$prefix-$code'));

/// La cruz de una etiqueta.
Finder cross(String prefix, String code) =>
    find.descendant(of: tag(prefix, code), matching: find.byIcon(Icons.close));

const String repoTags = 'repo-test/repo-language';
const String myTags = 'use-language';

void main() {
  group('lo que traduce un repositorio', () {
    testWidgets('solo los que mantiene salen como etiqueta', (tester) async {
      await pumpLanguages(tester);

      for (final code in const ['es', 'va', 'en']) {
        expect(tag(repoTags, code), findsOneWidget);
      }
      // Los que Didacta sabe imprimir y el repositorio no traduce están en el
      // desplegable, no como un chip apagado al lado de los que sí.
      for (final code in const ['ca', 'fr', 'de']) {
        expect(tag(repoTags, code), findsNothing);
      }
      expect(find.byKey(const Key('$repoTags-choice')), findsOneWidget);
    });

    testWidgets('añadir pasa por el desplegable y su botón', (tester) async {
      final it = await pumpLanguages(tester);

      final add = find.byKey(const Key('$repoTags-add'));
      // Sin nada elegido, el botón no hace nada.
      expect(tester.widget<OutlinedButton>(add).onPressed, isNull);

      await tester.tap(find.byKey(const Key('$repoTags-choice')));
      await settle(tester);
      await tester.tap(find.text('Français').last);
      await settle(tester);
      expect(it.gateway.commits, isEmpty);

      await tester.tap(add);
      await settle(tester);

      expect(
        it.gateway.commits.single.text,
        contains('languages: [es, va, en, fr]'),
      );
    });

    testWidgets('quitar pregunta, y cancelar no escribe', (tester) async {
      final it = await pumpLanguages(tester);

      await tester.tap(cross(repoTags, 'en'));
      await settle(tester);

      expect(find.text('¿Quitar English de repo?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('remove-language-cancel')));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(it.gateway.commits, isEmpty);
    });

    testWidgets('quitar y decir que sí lo saca de didacta.yaml', (
      tester,
    ) async {
      final it = await pumpLanguages(tester);

      await tester.tap(cross(repoTags, 'en'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('remove-language-confirm')));
      await settle(tester);

      expect(it.gateway.commits.single.text, contains('languages: [es, va]'));
    });

    testWidgets('el de referencia y el que está en uso no tienen cruz', (
      tester,
    ) async {
      // Quitarlos dejaría un repositorio que el motor no lee entero; ofrecer
      // la cruz para luego negarse en el diálogo sería peor que no ofrecerla.
      await pumpLanguages(tester);

      expect(cross(repoTags, 'es'), findsNothing);
      expect(cross(repoTags, 'va'), findsNothing);
      expect(cross(repoTags, 'en'), findsOneWidget);
      expect(
        find.descendant(
          of: tag(repoTags, 'es'),
          matching: find.text(' · referencia'),
        ),
        findsOneWidget,
      );
    });
  });

  group('con los que trabajo', () {
    testWidgets('quitar uno pregunta y lo pasa al desplegable', (tester) async {
      final it = await pumpLanguages(tester);

      await tester.tap(cross(myTags, 'en'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('remove-language-confirm')));
      await settle(tester);

      expect(it.session.isLanguageEnabled('en'), isFalse);
      expect(tag(myTags, 'en'), findsNothing);
      expect(find.byKey(const Key('$myTags-choice')), findsOneWidget);
      // Es una preferencia: ningún fichero del repositorio se entera.
      expect(it.gateway.commits, isEmpty);
    });

    testWidgets('y volver a añadirlo lo enciende', (tester) async {
      final it = await pumpLanguages(tester);
      await it.session.setLanguageEnabled('en', false);
      await settle(tester);

      await tester.tap(find.byKey(const Key('$myTags-choice')));
      await settle(tester);
      await tester.tap(find.text('English').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('$myTags-add')));
      await settle(tester);

      expect(it.session.isLanguageEnabled('en'), isTrue);
      expect(tag(myTags, 'en'), findsOneWidget);
    });

    testWidgets('el último que queda no se quita', (tester) async {
      // Sin ninguno encendido no hay filtro, así que quitar el último haría
      // volver a los tres de golpe.
      final it = await pumpLanguages(tester);
      await it.session.setLanguageEnabled('en', false);
      await it.session.setLanguageEnabled('va', false);
      await settle(tester);

      expect(tag(myTags, 'es'), findsOneWidget);
      expect(cross(myTags, 'es'), findsNothing);
    });
  });
}
