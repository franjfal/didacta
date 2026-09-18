/// Sacar el material de la aplicación: dónde está el botón de llevárselo.
///
/// Lo que estas pruebas fijan no es el flujo --el diálogo del sistema no se
/// puede abrir aquí-- sino dónde se puede pedir, que es lo que estaba mal:
/// exportar un curso vivía detrás de unos puntos suspensivos y de un documento
/// no se podía pedir en absoluto.
///
/// Y las dos reglas que hacen que el botón no engañe:
///
/// * **no aparece si no hay nada compilado.** Un botón que solo sabe decir
///   «no había nada» estorba, y la misma regla vale para el de mirar el PDF;
/// * **no pide permiso de escritura.** Exportar copia lo que ya está hecho y
///   no toca el repositorio, así que también lo hace quien solo lo tiene para
///   leer -- justo lo contrario que copiar un curso a otro.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/compiler.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/courses_page.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ExistingOutput builtPdf(String profile) => ExistingOutput(
  profile: profile,
  label: profile,
  family: 'notes',
  language: 'es',
  pdf: '/tmp/$profile.pdf',
  exists: true,
  stale: false,
);

Future<void> pumpYear(WidgetTester tester, {required FakeCompiler of}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    compilerOverride: of,
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(
          body: YearPage(courseId: 'am-iii', year: '2025-2026'),
        ),
      ),
    ),
  );
  await settle(tester);
}

Future<void> pumpCourses(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
  );
  await session.primeForTest(catalogue);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const Scaffold(body: CoursesPage()),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('un curso se exporta desde su fila, sin abrir ningún menú', (
    tester,
  ) async {
    // Estaba dentro de «…», que es donde van las operaciones que se hacen una
    // vez al año; repartir un curso se hace cada semana.
    await pumpCourses(tester);
    final export = find.byKey(const Key('export-year-am-iii-2025-2026'));
    expect(export, findsOneWidget);

    // Al lado de la estrella, que es donde se mira.
    final star = find.byKey(const Key('favourite-year-am-iii-2025-2026'));
    expect(tester.getCenter(export).dy, tester.getCenter(star).dy);

    // Y sin permiso de escritura no hay ni menú donde esconderlo, que es la
    // otra mitad: exportar copia lo compilado y no toca el repositorio.
    expect(find.byKey(const Key('year-menu-am-iii-2025-2026')), findsNothing);
  });

  testWidgets('un documento se exporta si tiene algo compilado', (
    tester,
  ) async {
    final compiler = FakeCompiler()
      ..documentOutputList = {
        'tema-1': [builtPdf('notes')],
      };
    await pumpYear(tester, of: compiler);

    expect(find.byKey(const Key('export-document-tema-1')), findsOneWidget);
    // Y de lo que no está compilado no se ofrece: no hay nada que copiar.
    expect(find.byKey(const Key('export-document-hoja-1')), findsNothing);
  });

  testWidgets('sin nada compilado no se ofrece exportar ningún documento', (
    tester,
  ) async {
    await pumpYear(tester, of: FakeCompiler());
    expect(find.byKey(const Key('export-document-tema-1')), findsNothing);
  });
}
