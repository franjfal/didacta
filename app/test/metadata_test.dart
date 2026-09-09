/// The metadata editor, driven end to end against a fake gateway.
///
/// The claim under test is the one that would be expensive to get wrong: an
/// edit made through the form changes the field it was asked about and leaves
/// the rest of the file -- including the migration provenance and the TODO
/// markers that are the work list for two thousand units -- exactly as it
/// was. So these tests read the committed text and look for the comments.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/content_gateway.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/metadata_editor.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

final Finder save = find.byKey(const Key('metadata-save'));
final Finder commit = find.byKey(const Key('metadata-commit'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeGateway> pumpMetadata(
  WidgetTester tester, {
  FakeGateway? gateway,
}) async {
  // A tall window on purpose: the form is a `ListView`, which does not build
  // what is off screen, and scroll choreography in a dozen tests is noise
  // that hides what each one is actually checking.
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used = gateway ?? FakeGateway();
  final catalogue = catalogueWith([unitJson()]);
  final session = FakeSession(gatewayOverride: used, catalogue: catalogue);
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: MetadataEditor(
            unit: catalogue.unitByPath(unitPath)!,
            session: session,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return used;
}

void main() {
  testWidgets('opens with the values the file has', (tester) async {
    await pumpMetadata(tester);

    expect(find.text('analysis.normed.definition'), findsWidgets);
    expect(find.text('Espacios normados'), findsOneWidget);
    // The kind is a chip, selected, with the Spanish name of `theory`.
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, kindName('theory')),
    );
    expect(chip.selected, isTrue);
    // And the tags are there as removable chips.
    expect(find.widgetWithText(InputChip, 'norma'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'banach'), findsOneWidget);
  });

  testWidgets('the save button is dead until something changes', (
    tester,
  ) async {
    await pumpMetadata(tester);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets('changing the kind counts as one line changed', (tester) async {
    await pumpMetadata(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, kindName('handout')));
    await settle(tester);

    // One line out, one line in: the whole point of the surgical edit.
    expect(find.text('+1 −1'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('saving shows the diff and then commits', (tester) async {
    final gateway = await pumpMetadata(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, kindName('handout')));
    await settle(tester);
    await tester.tap(save);
    await settle(tester);

    // The dialog shows the change rather than asserting it is small.
    expect(find.text('Guardar unit.yaml'), findsOneWidget);
    expect(find.text('− kind: theory'), findsOneWidget);
    expect(find.text('+ kind: handout'), findsOneWidget);
    // And the message names the field, not the file.
    expect(find.textContaining('Cambiar kind'), findsOneWidget);

    await tester.tap(commit);
    await settle(tester);

    expect(gateway.commits, hasLength(1));
    final written = gateway.commits.single;
    expect(written.path, '$unitPath/unit.yaml');
    expect(written.sha, 'sha-$unitPath/unit.yaml');
    expect(written.text, contains('kind: handout'));

    // What this whole class exists for.
    expect(written.text, contains('# Migrated from:'));
    expect(written.text, contains('#   00classnotes/901Analysis'));
    expect(written.text, contains('# TODO: check the title against the'));
    expect(written.text, contains('# Only languages that exist are listed'));
    // And nothing else moved.
    expect(
      written.text,
      unitYaml.replaceFirst('kind: theory', 'kind: handout'),
    );
  });

  testWidgets('a title in a language that had none is added', (tester) async {
    final gateway = await pumpMetadata(tester);

    await tester.enterText(
      find.byKey(const ValueKey('title-va')),
      'Espais normats',
    );
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    expect(find.textContaining('Cambiar título va'), findsOneWidget);
    await tester.tap(commit);
    await settle(tester);

    final written = gateway.commits.single.text;
    expect(written, contains('  es: Espacios normados\n  va: Espais normats'));
    // Added under `title:`, so the comment above `es:` is still above `es:`.
    expect(written, contains('# TODO: check the title against the handout'));
  });

  testWidgets('a duration is written as a number, not a string', (
    tester,
  ) async {
    final gateway = await pumpMetadata(tester);

    await tester.enterText(find.widgetWithText(TextField, 'minutos'), '50');
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    // `duration_minutes: '50'` is a string and the schema wants a number.
    expect(gateway.commits.single.text, contains('duration_minutes: 50\n'));
  });

  testWidgets('objectives go in as a block list', (tester) async {
    final gateway = await pumpMetadata(tester);

    await tester.tap(find.textContaining('Añadir: Qué sabe hacer'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('item-0-')),
      'Reconocer una norma',
    );
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(
      gateway.commits.single.text,
      contains('objectives:\n  - Reconocer una norma\n'),
    );
  });

  testWidgets('a tag is removed without touching the others', (tester) async {
    final gateway = await pumpMetadata(tester);

    // The delete affordance of an InputChip, whichever icon the theme gives
    // it: the chip renders one and only one, next to its label.
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(InputChip, 'norma'),
            matching: find.byType(Icon),
          )
          .last,
    );
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(gateway.commits.single.text, contains('tags: [banach]'));
  });

  testWidgets('a read-only gateway offers no save', (tester) async {
    await pumpMetadata(tester, gateway: FakeGateway(writable: false));

    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    // And the chips do not respond, so nothing can be typed that cannot be
    // kept.
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, kindName('handout')),
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('the raw file is one tap away', (tester) async {
    await pumpMetadata(tester);

    await tester.tap(find.byIcon(Icons.code));
    await settle(tester);

    // The whole file, comments included, in a text field.
    expect(find.textContaining('# Migrated from:'), findsOneWidget);
  });

  testWidgets('a conflict is reported and the edit is kept', (tester) async {
    await pumpMetadata(
      tester,
      gateway: FakeGateway(
        failWith: const ContentException(
          'unit.yaml ha cambiado en el repositorio',
          kind: ContentFailure.conflict,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, kindName('handout')));
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    await tester.tap(commit);
    await settle(tester);

    expect(find.textContaining('ha cambiado'), findsWidgets);
    // Still selected: the work is not thrown away by a failed save.
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, kindName('handout')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('a missing unit.yaml says so and offers a retry', (tester) async {
    await pumpMetadata(tester, gateway: FakeGateway(files: {}));

    expect(find.text('No se ha podido abrir unit.yaml'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('the unit page opens it from a tab', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gateway = FakeGateway();
    final catalogue = catalogueWith([unitJson()]);
    final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
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

    await tester.tap(find.text('unit.yaml'));
    await settle(tester);

    expect(find.text('IDENTIDAD'), findsOneWidget);
    expect(find.text('CLASIFICACIÓN'), findsOneWidget);
  });
}
