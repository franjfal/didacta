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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/data/catalogue_source.dart';
import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/main.dart';
import 'package:didacta_app/model/workspace.dart';
import 'package:didacta_app/state/session.dart';

import 'fixture.dart';

/// El contraste WCAG entre dos colores opacos.
double contrast(Color a, Color b) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final one = luminance(a);
  final two = luminance(b);
  return (math.max(one, two) + 0.05) / (math.min(one, two) + 0.05);
}

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

/// Arranca la aplicación dejando correr el reloj de verdad.
///
/// Hace falta cuando el arranque toca el disco: dentro de `testWidgets` el
/// tiempo es falso, y una lectura de fichero se queda esperando para siempre
/// por mucho que se pumpee. Con `runAsync` corre de verdad, y después se
/// pinta con el reloj falso de siempre.
Future<void> pumpFromDisk(WidgetTester tester, Session session) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      DidactaApp(session: session, updates: offlineUpdates()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await settle(tester);
}

Session sessionWith({CatalogueSource? source, String? clonePath}) =>
    LocalSession(
      catalogueSource:
          source ?? StaticCatalogueSource(catalogueWith(defaultUnits())),
      tokenStore: StubStore(),
      preferences: MemoryPreferences(
        path: clonePath,
        repos: clonePath == null
            ? null
            : Workspace([
                ContentRepo(owner: 'x', name: 'repo', directory: clonePath),
              ]).toJson(),
      ),
    );

void main() {
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

      // Con un repositorio abierto: sin ninguno, que no haya catálogo no es
      // un fallo sino una instalación recién puesta, y la pantalla es otra.
      await pumpFromDisk(tester, sessionWith(clonePath: '/didacta-no-existe'));

      expect(find.text('No se pudo cargar el catálogo'), findsOneWidget);
      expect(find.textContaining('/didacta-no-existe'), findsWidgets);
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
          session: sessionWith(clonePath: clone.path),
          updates: offlineUpdates(),
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

  group('sin repositorios, la aplicación abre y dice qué falta', () {
    // Antes, sin clon configurado, la primera pantalla era «No se pudo cargar
    // el catálogo» con una dirección relativa que en escritorio no resuelve
    // --y desde ahí no se llegaba a Ajustes, que vive dentro del router y el
    // router solo existe cuando hay catálogo--. No es un fallo: es que
    // todavía no se le ha dicho con qué trabajar.

    testWidgets('abre vacía, sin pantalla de fallo', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        DidactaApp(
          session: sessionWith(
            source: const HttpCatalogueSource(base: 'http://127.0.0.1:1/nada'),
          ),
          updates: offlineUpdates(),
        ),
      );
      await settle(tester);

      expect(find.text('No se pudo cargar el catálogo'), findsNothing);
      expect(find.text('didacta index'), findsNothing);
      // Y con el camino delante, que es lo que faltaba.
      expect(find.byKey(const Key('go-to-settings')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in sizes.entries) {
      testWidgets('y el aviso cabe (${size.key})', (tester) async {
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          DidactaApp(
            session: sessionWith(
              source: const HttpCatalogueSource(
                base: 'http://127.0.0.1:1/nada',
              ),
            ),
            updates: offlineUpdates(),
          ),
        );
        await settle(tester);

        expect(find.byKey(const Key('go-to-settings')), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'desborda en ${size.key}',
        );
      });
    }
  });
}
