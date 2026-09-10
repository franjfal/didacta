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

import 'dart:io';

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
      expect(tester.takeException(), isNull, reason: 'desborda en ${size.key}');
    });
  }

  testWidgets('con clon pero sin índice, el consejo es `didacta index`', (
    tester,
  ) async {
    // El otro fallo, que sí es el que el consejo arregla: la carpeta está
    // elegida y lo que falta es generar el índice. Se distingue del anterior
    // porque el consejo es distinto, y dar el que no toca cuesta una tarde.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final clone = Directory.systemTemp.createTempSync('didacta-sin-indice-');
    addTearDown(() => clone.deleteSync(recursive: true));

    // Dentro de `runAsync` porque leer del disco es asíncrono de verdad, y
    // el reloj de `testWidgets` es falso: sin esto la carga no termina nunca
    // y la pantalla se queda cargando.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        DidactaApp(
          session: sessionWith(
            auth: const UnavailableAuth(),
            clonePath: clone.path,
          ),
          firebaseReady: false,
        ),
      );
      // Pintando y esperando de verdad: `start()` sale de `initState`, así
      // que la lectura del disco ocurre entre fotogramas y hay que darle
      // tiempo real, no del reloj falso.
      for (var i = 0; i < 8; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await settle(tester);

    expect(find.text('No se pudo cargar el catálogo'), findsOneWidget);
    expect(find.textContaining('${clone.path}/generated'), findsWidgets);
    expect(find.text('didacta index'), findsOneWidget);
    expect(
      find.textContaining('No hay ninguna carpeta del repositorio'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  group('sin clon, la pantalla de fallo es una salida', () {
    // El fallo que esto coge ya ocurrió: una compilación de escritorio hecha
    // sin `--dart-define=DIDACTA_CLONE` abrió diciendo «no se pudo cargar el
    // catálogo» con el catálogo generado y en su sitio, y desde esa pantalla
    // no se podía llegar a Ajustes --que vive dentro del router, y el router
    // solo existe cuando hay catálogo-- así que no había forma de arreglarlo
    // desde la aplicación.

    testWidgets('dice que falta la carpeta, no que falte el índice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
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

      expect(
        find.textContaining('No hay ninguna carpeta del repositorio'),
        findsOneWidget,
      );
      // Y no el consejo que aquí no sirve: no falta ningún índice. Exacto
      // y no `textContaining`, porque el motivo del error sí puede
      // mencionarlo; lo que no tiene que estar es el consejo.
      expect(find.text('didacta index'), findsNothing);
      expect(find.byKey(const Key('choose-clone')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in sizes.entries) {
      testWidgets('y los dos botones caben (${size.key})', (tester) async {
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          DidactaApp(
            session: sessionWith(
              auth: const UnavailableAuth(),
              source: const HttpCatalogueSource(
                base: 'http://127.0.0.1:1/nada',
              ),
            ),
            firebaseReady: false,
          ),
        );
        await settle(tester);

        expect(find.byKey(const Key('choose-clone')), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'desborda en ${size.key}',
        );
      });
    }
  });
}
