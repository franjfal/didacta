/// The composition builder, driven end to end against a fake gateway.
///
/// What matters here, in order:
///
/// * a disabled entry stays visible and can be switched back on -- nine
///   hundred of them exist in the repository and turning some on is the
///   commonest edit after a migration;
/// * reordering writes the order and nothing else;
/// * a broken reference is shown in its place rather than omitted, because a
///   composition that hides what is missing looks complete and compiles
///   short;
/// * the commit shows its diff before it happens.
library;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/composition_editor.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

final Finder save = find.byKey(const Key('composition-save'));
final Finder commit = find.byKey(const Key('composition-commit'));
final Finder addUnit = find.byKey(const Key('add-unit'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeGateway> pumpComposition(
  WidgetTester tester, {
  FakeGateway? gateway,
  String documentId = 'tema-1',
}) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used = gateway ?? FakeGateway();
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: used, catalogue: catalogue);
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: CompositionEditor(
            courseId: 'am-iii',
            year: '2025-2026',
            documentId: documentId,
            session: session,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return used;
}

/// The composition as the file now has it, after whatever was committed.
List<String> committedEntries(FakeGateway gateway, [String id = 'tema-1']) =>
    [
      for (final entry
          in CompositionFile(gateway.commits.last.text).blockFor(id)!.entries)
        entry.toString(),
    ];

void main() {
  testWidgets('shows every entry, disabled ones included', (tester) async {
    await pumpComposition(tester);

    // The heading, by its Spanish title.
    expect(find.text('Normas'), findsOneWidget);
    // The two units that resolve, by title.
    expect(find.text('Espacios normados'), findsOneWidget);
    expect(find.text('Espacios de Banach'), findsOneWidget);
    // The disabled one, which the catalogue does not know: shown by path.
    expect(find.textContaining('analysis/normed/dedekind'), findsWidgets);
    // And the broken reference is named, not omitted.
    expect(
      find.textContaining('analysis/normed/no-existe (no existe)'),
      findsOneWidget,
    );
  });

  testWidgets('numbers only the active entries', (tester) async {
    await pumpComposition(tester);

    // Four active entries out of five, so the numbers run 1..4 and the
    // disabled one gets a dash rather than a number that skips.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsNothing);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('4 de 5 activas'), findsOneWidget);
  });

  testWidgets('the save button is dead until something changes',
      (tester) async {
    await pumpComposition(tester);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('switching a disabled entry on is one line', (tester) async {
    final gateway = await pumpComposition(tester);

    // The toggle of the row that is off.
    await tester.tap(find.byIcon(Icons.toggle_off_outlined));
    await settle(tester);

    expect(find.text('+1 −1'), findsOneWidget);
    expect(find.textContaining('5 de 5 activas'), findsOneWidget);

    await tester.tap(save);
    await settle(tester);
    // The message says what happened, not "edit year.yaml".
    expect(
      find.textContaining('Activar una entrada en la composición de tema-1'),
      findsOneWidget,
    );
    // The diff shows the file's own lines, indentation included: the marker,
    // then the line as it will be written.
    const indent = '      ';
    expect(
      find.text('− $indent# - unit: analysis/normed/dedekind'),
      findsOneWidget,
    );
    expect(
      find.text('+ $indent- unit: analysis/normed/dedekind'),
      findsOneWidget,
    );
    await tester.tap(commit);
    await settle(tester);

    expect(gateway.commits, hasLength(1));
    expect(committedEntries(gateway), [
      '- section: Normas',
      '- unit: analysis/normed/definition',
      '- unit: analysis/normed/banach',
      '- unit: analysis/normed/dedekind',
      '- unit: analysis/normed/no-existe',
    ]);
    // Everything else in the file is untouched, the other document included.
    expect(gateway.commits.single.text, contains('  - id: hoja-1'));
    expect(gateway.commits.single.text, contains('          # TODO: va'));
  });

  testWidgets('switching one off keeps it in place', (tester) async {
    final gateway = await pumpComposition(tester);

    await tester.tap(find.byIcon(Icons.toggle_on).first);
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    // The heading is off, still first, still carrying its title block.
    expect(committedEntries(gateway).first, '# - section: Normas');
    expect(gateway.commits.single.text, contains('      # - section:'));
    expect(gateway.commits.single.text, contains('          # es: Normas'));
  });

  testWidgets('dragging a row writes the new order and nothing else',
      (tester) async {
    final gateway = await pumpComposition(tester);

    // The second row's handle, dragged up past the first. Done as an
    // explicit gesture with intermediate moves rather than `tester.drag`: a
    // reorderable list tracks the pointer, and a single jump from down to up
    // never starts the drag.
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(5));
    final from = tester.getCenter(handles.at(1));
    final to = tester.getCenter(handles.at(0));

    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout);
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(Offset.lerp(from, to, step / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.moveTo(to - const Offset(0, 8));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await settle(tester);
    expect(
      tester.widget<FilledButton>(save).onPressed,
      isNotNull,
      reason: 'el arrastre no ha cambiado nada',
    );

    await tester.tap(save);
    await settle(tester);
    expect(
      find.textContaining('Cambiar el orden en la composición de tema-1'),
      findsOneWidget,
    );
    await tester.tap(commit);
    await settle(tester);

    expect(committedEntries(gateway), [
      '- unit: analysis/normed/definition',
      '- section: Normas',
      '- unit: analysis/normed/banach',
      '# - unit: analysis/normed/dedekind',
      '- unit: analysis/normed/no-existe',
    ]);
    // The heading kept its whole title block on the way past.
    expect(gateway.commits.single.text, contains('''
      - unit: analysis/normed/definition
      - section:
          es: Normas
          # TODO: va
          # TODO: en
'''));
    // And the rest of the file did not move.
    expect(gateway.commits.single.text, contains('    profiles: [handout, slides]'));
    expect(gateway.commits.single.text, contains('  - id: hoja-1'));
  });

  testWidgets('renaming a heading writes the language being browsed',
      (tester) async {
    final gateway = await pumpComposition(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Normas'),
      'Espacios normados y de Banach',
    );
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(
      gateway.commits.single.text,
      contains('          es: Espacios normados y de Banach'),
    );
    // The TODO markers for the languages still missing are not collateral.
    expect(gateway.commits.single.text, contains('          # TODO: va'));
    expect(gateway.commits.single.text, contains('          # TODO: en'));
  });

  testWidgets('adding a unit picks it from the library', (tester) async {
    final gateway = await pumpComposition(tester);

    await tester.tap(addUnit);
    await settle(tester);
    expect(find.text('Añadir una unidad'), findsOneWidget);
    // Units already in the document are shown and not selectable, because
    // "why can I not find it" deserves an answer.
    expect(find.text('ya está en este documento'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'ejercicios');
    await settle(tester);
    await tester.tap(find.text('Ejercicios de normas'));
    await settle(tester);

    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    // A unit under problems/ goes in as a `problem:` entry, which is what
    // the engine keys the answer levels off.
    expect(
      committedEntries(gateway).last,
      '- problem: analysis/normed/exercises',
    );
    // And the row is now in the list, numbered last among the active ones.
    expect(find.textContaining('5 de 6 activas'), findsOneWidget);
  });

  testWidgets('a heading can be added and named', (tester) async {
    final gateway = await pumpComposition(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Subapartado'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Título nuevo'),
      'Desigualdad triangular',
    );
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(gateway.commits.single.text, contains('      - subsection:'));
    expect(
      gateway.commits.single.text,
      contains('          es: Desigualdad triangular'),
    );
    // And the other languages start marked as pending, as the migrator does.
    expect(gateway.commits.single.text, contains('          # TODO: va'));
  });

  testWidgets('removing asks first, and says the unit is not deleted',
      (tester) async {
    final gateway = await pumpComposition(tester);

    await tester.tap(find.byIcon(Icons.close).first);
    await settle(tester);
    expect(find.text('¿Quitar de la composición?'), findsOneWidget);
    // And points at the softer option, which is usually the right one.
    expect(find.textContaining('desactívala en lugar de quitarla'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Quitar'));
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(committedEntries(gateway), hasLength(4));
    expect(committedEntries(gateway).first,
        '- unit: analysis/normed/definition');
  });

  testWidgets('cancelling the removal changes nothing', (tester) async {
    await pumpComposition(tester);

    await tester.tap(find.byIcon(Icons.close).first);
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await settle(tester);

    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('a read-only gateway gives no toggles and no save',
      (tester) async {
    await pumpComposition(tester, gateway: FakeGateway(writable: false));

    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.toggle_on).first,
        matching: find.byType(IconButton),
      ),
    ).onPressed, isNull);
    // And no way to add, so nothing can be built that cannot be kept.
    expect(addUnit, findsNothing);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
  });

  testWidgets('a document with one entry still works', (tester) async {
    await pumpComposition(tester, documentId: 'hoja-1');
    expect(find.text('Ejercicios de normas'), findsOneWidget);
    expect(find.textContaining('1 de 1 activas'), findsOneWidget);
  });

  testWidgets('a document that is not in year.yaml says so', (tester) async {
    await pumpComposition(tester, documentId: 'no-existe');
    expect(find.text('No se ha podido abrir la composición'), findsOneWidget);
    expect(find.textContaining('didacta index'), findsOneWidget);
  });

  testWidgets('a missing year.yaml offers a retry and Ajustes',
      (tester) async {
    await pumpComposition(tester, gateway: FakeGateway(files: {}));
    expect(find.text('No se ha podido abrir la composición'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('a conflict is reported and the order is kept', (tester) async {
    await pumpComposition(
      tester,
      gateway: FakeGateway(
        failWith: const ContentException(
          'year.yaml ha cambiado en el repositorio',
          kind: ContentFailure.conflict,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.toggle_off_outlined));
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(find.textContaining('ha cambiado'), findsWidgets);
    // The work survives: still five active.
    expect(find.textContaining('5 de 5 activas'), findsOneWidget);
  });
}
