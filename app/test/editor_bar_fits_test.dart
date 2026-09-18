/// Que la barra del editor quepa. A todos los anchos, no al que se probó.
///
/// Esto existe porque la misma cosa ha fallado tres veces seguidas: entra un
/// botón nuevo, se prueba en una ventana grande, y se desborda en una mediana.
/// Y una barra que se desborda **esconde su propio botón de guardar**, que en
/// una tableta es la pantalla entera inservible.
///
/// Un desbordamiento en Flutter es una excepción de renderizado, así que basta
/// con dibujarla y mirar si saltó.
@TestOn('vm')
library;

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/unit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fixture.dart';

const String here = 'content/analysis/normed/definition';

/// Los anchos donde se ha roto, y los de alrededor.
///
/// El modo lado a lado hace paneles de un tercio de ventana, así que los
/// pequeños son tan reales como los grandes.
const List<double> widths = [
  420,
  520,
  620,
  700,
  760,
  800,
  860,
  915,
  1000,
  1100,
  1280,
  1600,
];

Map<String, dynamic> unitHere() => {
  ...unitJson(),
  'languages': {
    'es': {'status': 'source', 'exists': true},
    'va': {'status': 'draft', 'exists': true},
  },
};

void main() {
  for (final width in widths) {
    testWidgets('a ${width.toInt()} px de ancho no se desborda', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final catalogue = catalogueWith([unitHere()]);
      final session = FakeSession(
        gatewayOverride: FakeGateway(
          files: {
            '$here/es.tex': 'El original.\n',
            '$here/va.tex': 'La traducció.\n',
          },
        ),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);
      await session.useCloneForTest('/tmp/didacta-test');

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
      for (var i = 0; i < 12; i += 1) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tester.takeException(), isNull, reason: 'recién abierto');

      // Y con el fichero tocado, que es cuando salen «sin guardar» y
      // «Descartar» y la barra va más llena. Es el estado en el que se
      // desbordó las tres veces.
      await tester.enterText(find.byType(TextField).first, 'Tocado.\n');
      for (var i = 0; i < 12; i += 1) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tester.takeException(), isNull, reason: 'con cambios sin guardar');

      // Y que el botón de guardar siga ahí, que es el que no puede perderse.
      expect(find.byKey(const Key('editor-save')), findsOneWidget);
    });
  }
}
