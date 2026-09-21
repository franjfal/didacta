/// El editor de composición sobre un tema **vinculado**.
///
/// Existe por un fallo concreto y feo: al compartir un tema entre cursos, su
/// composición deja de estar en el `year.yaml` --allí solo queda una línea
/// `link:`-- y se muda a `shared/documents/<id>.yaml`. El editor seguía
/// leyendo el `year.yaml`, así que encontraba el tema, no encontraba ninguna
/// composición y se quedaba **en blanco**: ni reordenar, ni añadir, ni
/// quitar. Sin error, además, que es lo que lo hacía incomprensible.
///
/// Lo que se fija aquí:
///
/// * que el editor lea el fichero donde está la composición de verdad;
/// * que guarde en ese mismo, y no en el `year.yaml`;
/// * que las entradas comentadas y los comentarios sobrevivan, igual que en
///   un tema sin vincular;
/// * que **se avise** de que lo que se guarde cambia los demás cursos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/composition_editor.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

const String content = 'd-8a41f0c27b53';
const String sharedPath = 'shared/documents/$content.yaml';

/// El fichero compartido, con las incomodidades de siempre: una entrada
/// comentada --material que existe y este año no se da-- y un `# TODO`.
const String sharedYaml =
    '''
# Un documento compartido.

id: $content

kind: theory
themes: [tema-1]
title:
  es: "Tema 1. Espacios normados"
  # TODO: va
structure:
  - section:
      es: Normas
      # TODO: va
  - unit: analysis/normed/definition
  - unit: analysis/normed/banach
  # - unit: analysis/normed/dedekind
''';

/// El `year.yaml` del curso: el tema está, pero solo como ubicación.
const String linkedYear =
    '''
course: am-iii
year: 2025-2026
language: es

documents:
  - id: tema-1
    link: $content

  - id: hoja-1
    kind: problems
    title:
      es: Hoja 1
    structure:
      - problem: analysis/normed/exercises
''';

Map<String, dynamic> linkedCourse() {
  final course = courseJson();
  final years = <String, dynamic>{
    for (final entry in (course['years'] as Map).entries)
      '${entry.key}': {
        ...(entry.value as Map).cast<String, dynamic>(),
        if (entry.key == '2025-2026')
          'documents': [
            for (final document in ((entry.value as Map)['documents'] as List))
              if ((document as Map)['id'] == 'tema-1')
                {...document.cast<String, dynamic>(), 'content': content}
              else
                document.cast<String, dynamic>(),
          ],
      },
  };
  return {...course, 'years': years};
}

/// Las dos ubicaciones que dan este tema.
const List<Map<String, dynamic>> sharedIndex = [
  {
    'id': content,
    'declared': true,
    'kind': 'theory',
    'title': {'es': 'Tema 1. Espacios normados'},
    'placements': [
      {'course': 'am-iii', 'year': '2025-2026', 'document': 'tema-1'},
      {'course': 'am-iii', 'year': '2026-2027', 'document': 'tema-1'},
    ],
  },
];

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeGateway> pumpLinked(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final gateway = FakeGateway(
    files: {
      'courses/am-iii/2025-2026/year.yaml': linkedYear,
      sharedPath: sharedYaml,
    },
  );
  final catalogue = catalogueWith(
    defaultUnits(),
    courses: [linkedCourse()],
    shared: sharedIndex,
  );
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
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
            documentId: 'tema-1',
            session: session,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return gateway;
}

void main() {
  testWidgets('enseña las lecciones del tema, no una pantalla vacía', (
    tester,
  ) async {
    await pumpLinked(tester);
    expect(find.textContaining('Este documento no compone nada'), findsNothing);
    expect(find.text('analysis/normed/definition'), findsOneWidget);
    expect(find.text('analysis/normed/banach'), findsOneWidget);
  });

  testWidgets('la barra dice de qué fichero salen', (tester) async {
    await pumpLinked(tester);
    expect(find.textContaining(sharedPath), findsOneWidget);
    expect(
      find.textContaining('courses/am-iii/2025-2026/year.yaml'),
      findsNothing,
    );
  });

  testWidgets('lo comentado sigue estando, y se puede volver a activar', (
    tester,
  ) async {
    // Es el caso que más duele perder: material que existe y que este año no
    // se da.
    await pumpLinked(tester);
    expect(find.text('analysis/normed/dedekind'), findsOneWidget);
  });

  testWidgets('avisa de que esto se da en más sitios', (tester) async {
    await pumpLinked(tester);
    expect(
      find.textContaining('se da en 2 cursos y es el mismo en todos'),
      findsOneWidget,
    );
  });

  /// Activa la entrada comentada y confirma. Es la edición más corriente
  /// después de una migración, y la que menos margen deja: toca una sola
  /// línea del fichero.
  Future<void> switchOnAndCommit(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.toggle_off_outlined));
    await settle(tester);
    await tester.tap(find.byKey(const Key('composition-save')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('composition-commit')));
    await settle(tester);
  }

  testWidgets('editar escribe en el fichero compartido', (tester) async {
    final gateway = await pumpLinked(tester);
    await switchOnAndCommit(tester);

    expect(gateway.commits, hasLength(1));
    expect(gateway.commits.single.path, sharedPath);

    final written = CompositionFile.shared(
      gateway.commits.single.text,
    ).blockFor(CompositionFile.sharedDocument)!;
    expect(
      [for (final entry in written.entries) entry.enabled],
      // Las tres activas: la sección, las dos lecciones y la que acaba de
      // encenderse.
      [true, true, true, true],
    );
  });

  testWidgets('y el year.yaml del curso no se toca', (tester) async {
    final gateway = await pumpLinked(tester);
    await switchOnAndCommit(tester);
    expect(gateway.files['courses/am-iii/2025-2026/year.yaml'], linkedYear);
  });

  testWidgets('lo que escribe sigue siendo un fichero que se puede leer', (
    tester,
  ) async {
    final gateway = await pumpLinked(tester);
    await switchOnAndCommit(tester);

    // La cabecera, el id y el resto del tema siguen donde estaban: el editor
    // reescribe la composición y nada más.
    final text = gateway.commits.single.text;
    expect(text, contains('id: $content'));
    expect(text, contains('kind: theory'));
    expect(text, contains('themes: [tema-1]'));
    expect(text, contains('# TODO: va'));
    expect(text, contains('- unit: analysis/normed/dedekind'));
  });
}
