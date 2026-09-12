/// Los tres campos de un problema, en la pantalla de la unidad.
///
/// Lo que hay que demostrar no es que se vean tres cajas, sino que son una
/// **vista del fichero**: lo que se escribe en ellas acaba en el `.tex` con
/// sus entornos, guardar guarda eso, y volver al LaTeX enseña exactamente lo
/// mismo. Un segundo editor con su propio camino hasta el fichero sería dos
/// sitios donde perder texto.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';

import 'fixture.dart';

const String problemPath = 'problems/analysis/normed/exercises';

const String problemTex = r'''
\begin{exercise}
Derivar $f(x) = x^2$.
\end{exercise}
\medskip

\begin{solution}
Por la regla de la potencia.
\end{solution}
''';

final Finder statement = find.byKey(const Key('problem-exercise'));
final Finder answer = find.byKey(const Key('problem-answer'));
final Finder solution = find.byKey(const Key('problem-solution'));
final Finder save = find.byKey(const Key('editor-save'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeGateway> pumpUnit(
  WidgetTester tester, {
  String path = problemPath,
  String? text,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final gateway = FakeGateway(
    files: {
      '$path/es.tex': text ?? problemTex,
      '$path/unit.yaml': unitYaml,
      'courses/am-iii/2025-2026/year.yaml': yearYaml,
    },
  );
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: gateway, catalogue: catalogue);
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(body: UnitPage(unitPath: path)),
      ),
    ),
  );
  await settle(tester);
  return gateway;
}

void main() {
  testWidgets('un problema se edita por campos, no como un .tex', (
    tester,
  ) async {
    await pumpUnit(tester);

    expect(find.text('Enunciado'), findsOneWidget);
    expect(find.text('Resultado'), findsOneWidget);
    expect(find.text('Solución detallada'), findsOneWidget);

    // Con lo que había en cada entorno, en su campo.
    expect(
      tester.widget<TextField>(statement).controller!.text,
      r'Derivar $f(x) = x^2$.',
    );
    expect(
      tester.widget<TextField>(solution).controller!.text,
      'Por la regla de la potencia.',
    );
    expect(tester.widget<TextField>(answer).controller!.text, isEmpty);
  });

  testWidgets('una unidad de teoría se sigue editando como texto', (
    tester,
  ) async {
    // Los campos son de un problema: una lección no tiene enunciado ni
    // solución, y ofrecérselos sería inventarle una estructura.
    await pumpUnit(tester, path: 'content/analysis/normed/definition');
    expect(find.text('Enunciado'), findsNothing);
    expect(find.byKey(const Key('problem-view-fields')), findsNothing);
  });

  testWidgets('escribir el resultado lo mete en su entorno', (tester) async {
    // Es el campo que ninguno de los 429 ficheros del repositorio usa: el
    // entorno existe desde el principio y no lo rellena nadie porque hay que
    // acordarse de escribirlo.
    final gateway = await pumpUnit(tester);

    await tester.enterText(answer, r"$f'(x) = 2x$");
    await settle(tester);

    await tester.tap(save);
    await settle(tester);
    await tester.tap(find.byKey(const Key('commit-save')));
    await settle(tester);

    final written = gateway.commits.single.text;
    expect(written, contains(r'\begin{answer}'));
    expect(written, contains(r"$f'(x) = 2x$"));
    // En su sitio: detrás del enunciado y delante de la solución.
    expect(
      written.indexOf(r'\begin{answer}'),
      greaterThan(written.indexOf(r'\end{exercise}')),
    );
    expect(
      written.indexOf(r'\begin{answer}'),
      lessThan(written.indexOf(r'\begin{solution}')),
    );
    // Y lo que había alrededor sigue ahí.
    expect(written, contains(r'\medskip'));
    expect(written, contains('Por la regla de la potencia.'));
  });

  testWidgets('el LaTeX enseña lo mismo que los campos', (tester) async {
    await pumpUnit(tester);
    await tester.enterText(statement, r'Derivar $f(x) = x^3$.');
    await settle(tester);

    await tester.tap(find.byKey(const Key('problem-view-text')));
    await settle(tester);

    expect(statement, findsNothing);
    expect(find.textContaining(r'\begin{exercise}'), findsWidgets);
    expect(find.textContaining(r'Derivar $f(x) = x^3$.'), findsWidgets);
  });

  testWidgets('un fichero con tres problemas lo dice y no los parte', (
    tester,
  ) async {
    await pumpUnit(tester, text: '$problemTex\n$problemTex');
    expect(find.textContaining('no son tres campos'), findsOneWidget);
    expect(find.textContaining('2 problemas'), findsOneWidget);
    // Y el texto sigue estando a un botón.
    expect(find.byKey(const Key('problem-view-text')), findsOneWidget);
  });
}
