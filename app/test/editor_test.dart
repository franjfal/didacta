/// The editor, driven end to end against a fake gateway.
///
/// A widget test rather than a screenshot, because what matters is the
/// behaviour that is expensive to get wrong and invisible when it is:
///
/// * saving asks for a message and produces a commit;
/// * the save button is dead when there is nothing to save, and when the
///   gateway cannot write at all;
/// * a conflict does not silently overwrite, and the text survives it;
/// * a language that does not exist yet opens with the original to translate
///   from, not a blank page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

Future<void> pumpEditor(
  WidgetTester tester, {
  required FakeGateway gateway,
  List<Map<String, dynamic>>? units,
}) async {
  final catalogue = catalogueWith(units ?? [unitJson()]);
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  // The catalogue is handed over rather than fetched, so `start()` is not
  // needed and Firebase is never touched.
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: UnitPage(unitPath: unitPath)),
      ),
    ),
  );
  await settle(tester);
}

/// The save button in the editor bar, and the one in the commit dialog.
///
/// Addressed by key rather than by label because both say "Guardar" -- which
/// is right, it is what both do -- so a finder on the text taps whichever
/// comes first once the dialog is open.
final Finder barSave = find.byKey(const Key('editor-save'));
final Finder dialogSave = find.byKey(const Key('commit-save'));

/// Pumps a bounded number of frames.
///
/// Not `pumpAndSettle`: this screen shows a `CircularProgressIndicator` while
/// a file loads and while a save is in flight, and an indefinite progress
/// animation never settles, so `pumpAndSettle` times out rather than
/// returning.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('opens the reference language with its content', (tester) async {
    final gateway = FakeGateway();
    await pumpEditor(tester, gateway: gateway);

    expect(find.text('Espacios normados'), findsOneWidget);
    expect(find.text('El contenido original en castellano.'), findsOneWidget);
  });

  testWidgets('the save button is dead until something changes', (
    tester,
  ) async {
    await pumpEditor(tester, gateway: FakeGateway());

    final button = tester.widget<FilledButton>(barSave);
    // Disabled rather than hidden, so it does not move as you type.
    expect(button.onPressed, isNull);
  });

  testWidgets('editing then saving asks for a message and commits', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await pumpEditor(tester, gateway: gateway);

    await tester.enterText(find.byType(TextField), 'Texto nuevo');
    await tester.pump();

    // Now live.
    final button = tester.widget<FilledButton>(barSave);
    expect(button.onPressed, isNotNull);

    await tester.tap(barSave);
    await settle(tester);

    // The message is asked for, and pre-filled with something meaningful --
    // a log full of "edit file" is a log nobody reads.
    expect(find.text('Guardar como commit'), findsOneWidget);
    expect(find.textContaining('Editar la versión es'), findsOneWidget);

    await tester.tap(dialogSave);
    await settle(tester);

    expect(gateway.commits, hasLength(1));
    final commit = gateway.commits.single;
    expect(commit.path, '$unitPath/es.tex');
    expect(commit.text, 'Texto nuevo');
    expect(commit.message, contains('Espacios normados'));
    // The sha the content was read at: what makes this a compare-and-set.
    expect(commit.sha, 'sha-$unitPath/es.tex');
  });

  testWidgets('a read-only gateway gives a read-only editor', (tester) async {
    // An editor that offers a save and then fails has already cost someone
    // their work, so the whole field is read-only up front.
    await pumpEditor(tester, gateway: FakeGateway(writable: false));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);

    final button = tester.widget<FilledButton>(barSave);
    expect(button.onPressed, isNull);
  });

  testWidgets('a conflict is reported and the text is kept', (tester) async {
    final gateway = FakeGateway(
      failWith: const ContentException(
        'ha cambiado en el repositorio',
        kind: ContentFailure.conflict,
      ),
    );
    await pumpEditor(tester, gateway: gateway);

    await tester.enterText(find.byType(TextField), 'Mi versión');
    await tester.pump();
    await tester.tap(barSave);
    await settle(tester);
    await tester.tap(dialogSave);
    await settle(tester);

    expect(gateway.commits, isEmpty);
    // Says what happened, and tells the author to reload rather than retry.
    expect(find.textContaining('ha cambiado'), findsWidgets);
    // And the work is still there.
    expect(find.text('Mi versión'), findsOneWidget);
  });

  testWidgets('a language that does not exist opens from the original', (
    tester,
  ) async {
    // A translator should have the source text in front of them, not a blank
    // page.
    final gateway = FakeGateway();
    await pumpEditor(tester, gateway: gateway);

    await tester.tap(find.text('va'));
    await settle(tester);

    expect(find.textContaining('Traducción pendiente'), findsOneWidget);
    expect(
      find.textContaining('El contenido original en castellano.'),
      findsOneWidget,
    );
  });

  testWidgets('saving a new language suggests adding, not editing', (
    tester,
  ) async {
    final gateway = FakeGateway();
    await pumpEditor(tester, gateway: gateway);

    await tester.tap(find.text('va'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'El contingut en valencià.');
    await tester.pump();
    await tester.tap(barSave);
    await settle(tester);

    expect(find.textContaining('Añadir la versión va'), findsOneWidget);

    await tester.tap(dialogSave);
    await settle(tester);

    expect(gateway.commits.single.path, '$unitPath/va.tex');
    // No sha: the file does not exist yet, and passing one would claim it did.
    expect(gateway.commits.single.sha, '');
  });

  group('los idiomas lado a lado', () {
    /// La unidad con sitio de sobra: el modo lado a lado necesita 300 px por
    /// columna, y por debajo de eso se apaga a propósito.
    Future<FakeSession> pumpWide(
      WidgetTester tester, {
      bool split = false,
      bool panel = true,
    }) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Con el valenciano existiendo de verdad en el catálogo: si dijera
      // que falta, el editor lo abriría desde el original --que es lo
      // correcto-- y no se estaría probando lo de al lado.
      final catalogue = catalogueWith([
        unitJson(
          languages: const {
            'es': {'status': 'source', 'exists': true},
            'va': {'status': 'translated', 'exists': true},
            'en': {'status': 'missing', 'exists': false},
          },
        ),
      ]);
      final session = FakeSession(
        gatewayOverride: FakeGateway(
          files: {
            '$unitPath/es.tex': 'El original en castellano.',
            '$unitPath/va.tex': 'El original en valencià.',
          },
        ),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.setSplitEditors(split);
      await session.setUnitPanelVisible(panel);

      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(body: UnitPage(unitPath: unitPath)),
          ),
        ),
      );
      await settle(tester);
      return session;
    }

    testWidgets('apagado, se ve un idioma', (tester) async {
      await pumpWide(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('El original en castellano.'), findsOneWidget);
      expect(find.text('El original en valencià.'), findsNothing);
    });

    testWidgets('encendido, se ven a la vez y cada uno es su fichero', (
      tester,
    ) async {
      await pumpWide(tester, split: true);

      // Tres ficheros y no tres vistas de uno: cada panel trae su contenido.
      expect(find.text('El original en castellano.'), findsOneWidget);
      expect(find.text('El original en valencià.'), findsOneWidget);
      // Y cada uno con su propio botón de guardar, porque son tres commits.
      expect(find.byKey(const Key('editor-save')), findsNWidgets(3));
    });

    testWidgets('la casilla lo enciende y lo apaga', (tester) async {
      final session = await pumpWide(tester);

      await tester.tap(find.byKey(const Key('split-editors')));
      await settle(tester);
      expect(session.splitEditors, isTrue);
      expect(find.text('El original en valencià.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('split-editors')));
      await settle(tester);
      expect(session.splitEditors, isFalse);
      expect(find.text('El original en valencià.'), findsNothing);
    });

    testWidgets('el panel activo va marcado', (tester) async {
      // Con tres columnas de LaTeX idénticas en forma, saber cuál responde a
      // la pestaña de arriba deja de ser evidente.
      await pumpWide(tester, split: true);
      expect(find.text('activo'), findsOneWidget);
    });

    testWidgets('editar en un panel no toca el otro', (tester) async {
      await pumpWide(tester, split: true);

      int liveSaves() => tester
          .widgetList<FilledButton>(find.byKey(const Key('editor-save')))
          .where((button) => button.onPressed != null)
          .length;

      // De entrada hay uno vivo, y no es un fallo: el panel del inglés no
      // existe, así que se abre precargado desde el original y tiene algo
      // que guardar desde el primer momento.
      expect(liveSaves(), 1);

      await tester.enterText(
        find.byType(TextField).first,
        'Cambiado el castellano.',
      );
      await settle(tester);

      // Uno más, y solo uno: el valenciano sigue como estaba.
      expect(liveSaves(), 2);
      expect(find.text('Cambiado el castellano.'), findsOneWidget);
      expect(find.text('El original en valencià.'), findsOneWidget);
    });

    testWidgets('sin ancho para dos columnas lo dice, y no finge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final catalogue = catalogueWith([unitJson()]);
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.setSplitEditors(true);

      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(body: UnitPage(unitPath: unitPath)),
          ),
        ),
      );
      await settle(tester);

      expect(
        find.textContaining('No hay ancho para dos columnas'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('el panel de la derecha', () {
    Future<FakeSession> pumpWide(
      WidgetTester tester, {
      bool panel = true,
    }) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final catalogue = catalogueWith([unitJson()]);
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.setUnitPanelVisible(panel);

      await tester.pumpWidget(
        ChangeNotifierProvider<Session>.value(
          value: session,
          child: MaterialApp(
            theme: didactaTheme(),
            home: const Scaffold(body: UnitPage(unitPath: unitPath)),
          ),
        ),
      );
      await settle(tester);
      return session;
    }

    testWidgets('desplegado por defecto, porque dice dónde se usa', (
      tester,
    ) async {
      // Es la respuesta a «¿puedo cambiar esto?», y esconderlo de entrada
      // dejaría a alguien editando sin saberlo.
      await pumpWide(tester);
      expect(find.text('QUÉ ES'), findsOneWidget);
      expect(find.textContaining('SE USA EN 1 DOCUMENTO'), findsOneWidget);
    });

    testWidgets('se colapsa, y el texto se queda con el ancho', (tester) async {
      final session = await pumpWide(tester);
      final wide = tester.getSize(find.byType(TextField)).width;

      await tester.tap(find.byIcon(Icons.info));
      await settle(tester);

      expect(session.unitPanelVisible, isFalse);
      expect(find.text('QUÉ ES'), findsNothing);
      // Y el editor se ha quedado el sitio, que era el objetivo.
      expect(tester.getSize(find.byType(TextField)).width, greaterThan(wide));
    });

    testWidgets('vuelve a salir', (tester) async {
      await pumpWide(tester, panel: false);
      expect(find.text('QUÉ ES'), findsNothing);

      await tester.tap(find.byIcon(Icons.info_outline));
      await settle(tester);
      expect(find.text('QUÉ ES'), findsOneWidget);
    });
  });

  testWidgets('an unknown unit says so rather than crashing', (tester) async {
    final catalogue = catalogueWith([unitJson()]);
    final session = FakeSession(
      gatewayOverride: FakeGateway(),
      catalogue: catalogue,
    );
    await session.primeForTest(catalogue);

    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: didactaTheme(),
          home: const Scaffold(
            body: UnitPage(unitPath: 'content/no/such/unit'),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Unidad no encontrada'), findsOneWidget);
  });
}
