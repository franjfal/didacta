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
  final session = FakeSession(
    gatewayOverride: gateway,
    catalogue: catalogue,
  );
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
    expect(
      find.text('El contenido original en castellano.'),
      findsOneWidget,
    );
  });

  testWidgets('the save button is dead until something changes',
      (tester) async {
    await pumpEditor(tester, gateway: FakeGateway());

    final button = tester.widget<FilledButton>(barSave);
    // Disabled rather than hidden, so it does not move as you type.
    expect(button.onPressed, isNull);
  });

  testWidgets('editing then saving asks for a message and commits',
      (tester) async {
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
    expect(
      find.textContaining('Editar la versión es'),
      findsOneWidget,
    );

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

  testWidgets('a language that does not exist opens from the original',
      (tester) async {
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

  testWidgets('saving a new language suggests adding, not editing',
      (tester) async {
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
