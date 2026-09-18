/// El interruptor de la sangría: por idioma, en el `unit.yaml`.
///
/// Lo normal es que esté puesto, y por eso lo que se prueba con más cuidado
/// es lo otro: que apagarlo se guarde, que se guarde **solo para ese idioma**,
/// y que apagado el fichero salga del editor exactamente como entró. Una
/// casilla que dice que no toca nada y toca algo es peor que no tenerla.
@TestOn('vm')
library;

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fixture.dart';

const String here = 'content/analysis/normed/definition';

/// El `.tex` tal como lo deja un traductor: todo pegado a la izquierda.
const String flat =
    '\\begin{itemize}\n\\item Uno\n\\item Dos\n\\end{itemize}\n';

Map<String, dynamic> unitWith({bool? indentVa}) => {
  ...unitJson(),
  'languages': {
    'es': {'status': 'source', 'exists': true},
    'va': {'status': 'draft', 'exists': true, 'indent': ?indentVa},
  },
};

Future<(FakeSession, FakeGateway)> ready({bool? indentVa}) async {
  final gateway = FakeGateway(
    files: {
      '$here/unit.yaml':
          'kind: theory\n'
          'title:\n'
          '  es: Una definición\n'
          'languages:\n'
          '  es: {status: source}\n'
          '  va: {status: draft}\n',
      '$here/es.tex': 'El original.\n',
      '$here/va.tex': flat,
    },
  );
  final catalogue = catalogueWith([unitWith(indentVa: indentVa)]);
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);
  await session.useCloneForTest('/tmp/didacta-test');
  return (session, gateway);
}

Unit theUnit(FakeSession session) =>
    session.catalogue.units.firstWhere((u) => u.path == here);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('lo que dice el catálogo', () {
    test('sin decir nada, se sangra', () {
      final unit = Unit.fromJson(unitWith());
      expect(unit.indentsIn('va'), isTrue);
      expect(unit.indentOff, isEmpty);
    });

    test('apagado en un idioma, sigue puesto en los demás', () {
      final unit = Unit.fromJson(unitWith(indentVa: false));
      expect(unit.indentsIn('va'), isFalse);
      expect(unit.indentsIn('es'), isTrue);
    });

    test('un idioma que no existe se sangra: no hay nada que respetar', () {
      expect(Unit.fromJson(unitWith()).indentsIn('en'), isTrue);
    });
  });

  group('guardarlo', () {
    test('apagarlo lo escribe en el unit.yaml', () async {
      final (session, gateway) = await ready();

      await session.setUnitIndent(
        unit: theUnit(session),
        language: 'va',
        on: false,
      );

      final written = gateway.commits.single;
      expect(written.path, '$here/unit.yaml');
      expect(written.text, contains('va: {status: draft, indent: false}'));
    });

    test('y no toca el otro idioma', () async {
      final (session, gateway) = await ready();

      await session.setUnitIndent(
        unit: theUnit(session),
        language: 'va',
        on: false,
      );

      expect(gateway.commits.single.text, contains('es: {status: source}'));
    });

    test('volver a encenderlo se escribe también', () async {
      // Aunque sea el valor por defecto: quien lo apagó y lo encendió quiere
      // verlo dicho en el fichero, no deducirlo de una ausencia.
      final (session, gateway) = await ready(indentVa: false);

      await session.setUnitIndent(
        unit: theUnit(session),
        language: 'va',
        on: true,
      );

      expect(gateway.commits.single.text, contains('indent: true'));
    });

    test('el mensaje del commit dice qué se apagó', () async {
      final (session, gateway) = await ready();

      await session.setUnitIndent(
        unit: theUnit(session),
        language: 'va',
        on: false,
      );

      expect(gateway.commits.single.message, contains('sangría'));
      expect(gateway.commits.single.message, contains('va'));
    });

    test('en un repositorio de solo lectura se niega', () async {
      final catalogue = catalogueWith([unitWith()]);
      final session = FakeSession(
        gatewayOverride: FakeGateway(writable: false),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);

      await expectLater(
        session.setUnitIndent(
          unit: theUnit(session),
          language: 'va',
          on: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('en el editor', () {
    testWidgets('la casilla sale puesta, y guardar ordena el fichero', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, gateway) = await ready();
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      final box = tester.widget<Checkbox>(
        find.byKey(const Key('editor-indent')),
      );
      expect(box.value, isTrue);

      // Se toca algo para que haya qué guardar, y se guarda.
      await tester.enterText(find.byType(TextField).first, '$flat% nota\n');
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('commit-save')));
      await settle(tester);

      final written = gateway.commits.last;
      expect(written.path, '$here/va.tex');
      expect(written.text, contains('  \\item Uno'));
    });

    testWidgets('apagada, el fichero se guarda letra por letra igual', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, gateway) = await ready(indentVa: false);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(
        tester.widget<Checkbox>(find.byKey(const Key('editor-indent'))).value,
        isFalse,
      );

      const raw = '\\begin{itemize}\n\\item Sin tocar\n\\end{itemize}\n';
      await tester.enterText(find.byType(TextField).first, raw);
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('commit-save')));
      await settle(tester);

      expect(gateway.commits.last.text, raw);
    });

    testWidgets('el botón de la barra ordena sin guardar', (tester) async {
      // El fallo que trajo este botón: sangrar solo pasaba al guardar, así
      // que un fichero escrito antes de que esto existiera se veía igual de
      // desordenado y parecía que la casilla no hacía nada. Nadie va a abrir
      // y guardar dos mil unidades para verlas bien puestas.
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, gateway) = await ready();
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      // El fichero está en disco sin sangrar y nadie lo ha tocado.
      expect(find.text('  \\item Uno'), findsNothing);
      expect(gateway.commits, isEmpty);

      await tester.tap(find.byKey(const Key('tidy-now')));
      await settle(tester);

      // Ordenado en pantalla y **sin guardar**: se mira antes de escribirlo.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, contains('  \\item Uno'));
      expect(gateway.commits, isEmpty);
      expect(find.text('Ordenado. Guarda para dejarlo así.'), findsOneWidget);
    });

    testWidgets('pulsarlo dos veces lo dice en lugar de callar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, _) = await ready();
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('tidy-now')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('tidy-now')));
      // Más largo que `settle`: el primer aviso se está retirando y el
      // segundo tiene que entrar, y las dos animaciones suman más de los 240
      // milisegundos que pumpea el resto de los tests.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Ya estaba ordenado.'), findsOneWidget);
    });

    testWidgets('apagada, el botón de ordenar no se ofrece', (tester) async {
      // Ofrecerlo en un idioma marcado para dejar quieto sería ofrecer justo
      // lo que se ha dicho que no se haga.
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, _) = await ready(indentVa: false);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const Key('tidy-now')), findsNothing);
    });

    testWidgets('pulsar la palabra ordena el fichero, sin tocar el ajuste', (
      tester,
    ) async {
      // La casilla dice si se ordena solo al guardar; la palabra lo ordena
      // ahora. Quien acaba de leer «Beautify» y quiere ver qué hace, pulsa la
      // palabra, y lo que **no** puede pasar es que eso apague el ajuste.
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, gateway) = await ready();
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('editor-beautify')));
      await settle(tester);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, contains('  \\item Uno'));
      // Ni ha guardado nada ni ha tocado el `unit.yaml`.
      expect(gateway.commits, isEmpty);
      expect(
        tester.widget<Checkbox>(find.byKey(const Key('editor-indent'))).value,
        isTrue,
      );
    });

    testWidgets('apagada, la palabra no ofrece ordenar', (tester) async {
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, _) = await ready(indentVa: false);
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      // La casilla sigue estando --es como se vuelve a encender-- pero el
      // botón de la barra de formato no.
      expect(find.byKey(const Key('editor-indent')), findsOneWidget);
      expect(find.byKey(const Key('tidy-now')), findsNothing);
    });

    testWidgets('la barra cabe con la casilla dentro', (tester) async {
      // La barra ya iba al límite antes de esto: con el botón de estado se
      // desbordó ochenta y seis píxeles. Un ancho de tableta es donde se ve.
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (session, _) = await ready();
      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(
              body: UnitPage(unitPath: here, language: 'va'),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const Key('editor-indent')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
