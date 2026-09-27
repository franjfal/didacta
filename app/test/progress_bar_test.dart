/// La barra de lo traducido enseña lo que dice.
///
/// Los tramos eran un `ColoredBox` sin hijo dentro de una fila, que mide cero
/// de alto: la barra enseñaba solo la vía gris aunque todo estuviera al día,
/// y la leyenda de al lado decía «58 al día».
library;

import 'package:didacta_app/model/library_tree.dart';
import 'package:didacta_app/ui/library_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpBar(WidgetTester tester, TranslationProgress progress) =>
    tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Center(
          child: SizedBox(width: 300, child: ProgressBar(progress: progress)),
        ),
      ),
    );

/// Los tramos pintados, con su color y su tamaño.
List<(Color, Size)> segments(WidgetTester tester) => [
  for (final element in find.byType(ColoredBox).evaluate())
    (
      (element.widget as ColoredBox).color,
      (element.renderObject! as RenderBox).size,
    ),
];

void main() {
  testWidgets('lo que está al día se ve, de la altura de la barra', (
    tester,
  ) async {
    await pumpBar(
      tester,
      const TranslationProgress(total: 4, done: 3, needsWork: 1, missing: 0),
    );
    final found = segments(tester);
    final done = found.where(
      (each) => each.$1 == DidactaPalette.light.accentDark,
    );
    final work = found.where((each) => each.$1 == DidactaPalette.light.ex);
    expect(done, hasLength(1));
    expect(work, hasLength(1));
    expect(done.single.$2.height, 6);
    // Tres de cuatro: el verde es tres veces el ámbar.
    expect(done.single.$2.width, closeTo(work.single.$2.width * 3, 0.5));
  });

  testWidgets('sin nada hecho, solo la vía', (tester) async {
    await pumpBar(
      tester,
      const TranslationProgress(total: 2, done: 0, needsWork: 0, missing: 2),
    );
    final colours = {DidactaPalette.light.accentDark, DidactaPalette.light.ex};
    expect(
      segments(tester).where((each) => colours.contains(each.$1)),
      isEmpty,
    );
  });
}
