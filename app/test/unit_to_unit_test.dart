/// Ir de una lección a otra sin pasar por ninguna otra pantalla.
///
/// Pasa con «Aprobar y siguiente» y con cualquier enlace de una lección a
/// otra. El `pageKey` de go_router es por ruta y no por dirección, así que
/// sin una clave propia la pantalla de la lección se reutilizaba entera, con
/// los editores ya cargados de la anterior: se veía su texto, y guardar lo
/// escribía en la nueva.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/main.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';

const String banach = 'content/analysis/normed/banach';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

String editorText(WidgetTester tester) {
  final fields = find.byType(EditableText).evaluate().toList();
  fields.sort((a, b) {
    final sa = (a.renderObject! as RenderBox).size;
    final sb = (b.renderObject! as RenderBox).size;
    return (sb.width * sb.height).compareTo(sa.width * sa.height);
  });
  return (fields.first.widget as EditableText).controller.text;
}

void main() {
  testWidgets('la lección nueva se abre con su texto, no con el de la '
      'anterior', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = FakeSession(
      gatewayOverride: FakeGateway(
        files: {
          '$unitPath/es.tex': 'El texto de la definición.\n',
          '$unitPath/unit.yaml': unitYaml,
          '$banach/es.tex': 'El texto de Banach.\n',
          '$banach/unit.yaml': unitYaml,
        },
      ),
      catalogue: catalogueWith(defaultUnits()),
    );
    await tester.pumpWidget(
      DidactaApp(session: session, updates: offlineUpdates()),
    );
    await settle(tester);
    final router = GoRouter.of(tester.element(find.byType(DidactaShell)));

    router.go('/unit/$unitPath?lang=es');
    await settle(tester);
    expect(editorText(tester), 'El texto de la definición.\n');

    router.go('/unit/$banach?lang=es');
    await settle(tester);
    expect(editorText(tester), 'El texto de Banach.\n');
  });
}
