/// Arranque, en las configuraciones en las que la aplicación arranca de verdad.
///
/// Existe por un fallo concreto y del peor tipo: en el build de escritorio no
/// hay `GoogleService-Info.plist`, Firebase no arrancaba --previsto y
/// capturado-- y justo después `main` construía `DidactaAuth`, que lee
/// `FirebaseAuth.instance` en su constructor. La excepción salía de `main`
/// antes de `runApp`, así que la ventana se abría negra y el motivo solo
/// estaba en un log que nadie ve.
///
/// Ningún test de pantalla lo habría cogido: todos montan la pantalla, que es
/// justo el paso al que no se llegaba. Así que estos montan [DidactaApp], que
/// es lo que monta `main`.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/auth.dart';
import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

const Map<String, Size> sizes = {
  'móvil': Size(390, 844),
  'tableta': Size(834, 1112),
  'escritorio': Size(1440, 900),
};

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Session sessionWith({
  required AuthSession auth,
  CatalogueSource? source,
  String? clonePath,
}) => Session(
  catalogueSource:
      source ?? StaticCatalogueSource(catalogueWith(defaultUnits())),
  auth: auth,
  tokenStore: StubStore(),
  apiBase: '',
  contentOwner: 'franjfal',
  contentRepo: 'didacta_db',
  contentBranch: 'main',
  preferences: MemoryPreferences(path: clonePath),
);

void main() {
  testWidgets('sin Firebase arranca y llega a la biblioteca', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      DidactaApp(
        session: sessionWith(auth: const UnavailableAuth()),
        // Como en escritorio: Firebase no ha arrancado.
        firebaseReady: false,
      ),
    );
    await settle(tester);

    // La biblioteca, no una pantalla en blanco. Dos veces: en la
    // navegación y en la cabecera de la página.
    expect(find.text('Biblioteca'), findsNWidgets(2));
    expect(find.textContaining('4 unidades'), findsOneWidget);
    // Y lo dice en lugar de fingir que se puede iniciar sesión.
    expect(find.textContaining('Firebase no ha arrancado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con Firebase arranca sin la advertencia', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      DidactaApp(session: sessionWith(auth: StubAuth()), firebaseReady: true),
    );
    await settle(tester);

    expect(find.text('Biblioteca'), findsNWidgets(2));
    expect(find.textContaining('Firebase no ha arrancado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A tres anchos: es la pantalla que ningún otro test alcanza --todos
  // tienen un catálogo que carga-- y es justo donde se colaba un
  // desbordamiento que tapaba el motivo, que es lo único que hay en ella.
  for (final size in sizes.entries) {
    testWidgets('un catálogo que no carga dice de dónde leyó (${size.key})', (
      tester,
    ) async {
      tester.view.physicalSize = size.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        DidactaApp(
          session: sessionWith(
            auth: const UnavailableAuth(),
            source: const HttpCatalogueSource(base: 'http://127.0.0.1:1/nada'),
          ),
          firebaseReady: false,
        ),
      );
      await settle(tester);

      expect(find.text('No se pudo cargar el catálogo'), findsOneWidget);
      expect(find.textContaining('http://127.0.0.1:1/nada'), findsWidgets);
      expect(find.textContaining('didacta index'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'desborda en ${size.key}');
    });
  }
}
