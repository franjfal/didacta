/// «En el texto», en el buscador de la biblioteca.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/library_place.dart';
import 'package:didacta_app/model/text_search.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final Finder chip = find.byKey(const Key('search-in-text'));

Future<FakeClone> pumpLibrary(
  WidgetTester tester, {
  bool clone = true,
  LibraryPlace place = const LibraryPlace(),
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = FakeClone()
    ..lines = const [
      // «Espacios de Banach» no dice «completitud» en su título: lo dice
      // dentro, que es lo que esto tiene que encontrar.
      TextHit(
        path: 'content/analysis/normed/banach/es.tex',
        line: 7,
        text: 'Un espacio de Banach es un normado con completitud.',
      ),
    ];
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    cloneOverride: clone ? fake : null,
  );
  await session.primeForTest(catalogue);
  if (clone) await session.useCloneForTest('/tmp/didacta-test');
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: LibraryPage(place: place)),
      ),
    ),
  );
  await settle(tester);
  return fake;
}

void main() {
  testWidgets('sin copia local no se ofrece', (tester) async {
    await pumpLibrary(tester, clone: false);
    expect(chip, findsNothing);
  });

  testWidgets('encuentra lo que la lección dice dentro, con su línea', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField).first, 'completitud');
    await settle(tester);
    // Por el título, nada.
    expect(find.text('Nada coincide'), findsOneWidget);

    await tester.tap(chip);
    await settle(tester);
    expect(find.text('Espacios de Banach'), findsOneWidget);
    expect(
      find.byKey(const Key('search-line-content/analysis/normed/banach')),
      findsOneWidget,
    );
    expect(find.textContaining('es · línea 7'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('search-summary'))).data,
      contains('1 por lo que dicen dentro'),
    );
  });

  testWidgets('con una errata encuentra lo mismo, y dice que se parece', (
    tester,
  ) async {
    await pumpLibrary(tester, clone: false);
    await tester.enterText(find.byType(TextField).first, 'Espacois');
    await settle(tester);
    expect(find.text('Espacios de Banach'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('search-summary'))).data,
      contains('ninguna tal cual, se parecen a lo que buscas'),
    );
  });

  testWidgets('desde la dirección, y los filtros siguen mandando', (
    tester,
  ) async {
    // `/?q=completitud&texto=1&bloque=…`: se abre buscando dentro, y lo
    // encontrado ahí pasa por los mismos filtros que lo demás.
    await pumpLibrary(
      tester,
      place: const LibraryPlace(query: 'completitud', inText: true),
    );
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
    expect(find.text('Espacios de Banach'), findsOneWidget);
  });

  testWidgets('un bloque que la deja fuera la deja fuera', (tester) async {
    await pumpLibrary(
      tester,
      place: const LibraryPlace(
        query: 'completitud',
        inText: true,
        block: 'problems',
      ),
    );
    expect(find.text('Espacios de Banach'), findsNothing);
  });
}
