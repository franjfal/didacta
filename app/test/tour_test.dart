/// El tour guiado, sobre el armazón de verdad.
///
/// Lo que importa de un tutorial no es que exista: es que no se quede
/// señalando el vacío, que se pueda cerrar, y que cerrarlo signifique algo.
/// Eso es lo que se prueba aquí.
@TestOn('vm')
library;

import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/shell.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fixture.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// El armazón con el velo del tour por encima, como en la aplicación.
Future<TourController> pumpShell(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  List<TourStep> steps = defaultTour,
  Future<void> Function()? onFinished,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // Las claves son de módulo: sin limpiarlas, un test hereda las del
  // anterior, que apuntan a widgets que ya no existen.
  tourTargets.clear();

  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
  );
  await session.primeForTest(catalogue);
  // Con un repositorio abierto: la barra de arriba --que es uno de los
  // objetivos del recorrido-- no se dibuja sin ninguno, y el tour se salta
  // los pasos que apuntan a algo que no está. Un armazón sin repositorios no
  // es el estado en el que corre el tour: corre después de configurarlo.
  await session.useCloneForTest('/tmp/didacta-test');

  final controller = TourController(steps: steps, onFinished: onFinished);

  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: MaterialApp(
        theme: didactaTheme(),
        home: const DidactaShell(location: '/', child: SizedBox.shrink()),
        // En el `builder`, por encima del `Navigator`, como en `main.dart`:
        // ahí no hay `Overlay`, y un globo que lo necesite --una ayuda
        // emergente-- solo se cae en ese sitio.
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            TourOverlay(controller: controller),
          ],
        ),
      ),
    ),
  );
  await settle(tester);
  return controller;
}

void main() {
  testWidgets('señala el carril y va avanzando', (tester) async {
    final tour = await pumpShell(tester);
    tour.start();
    await settle(tester);

    expect(find.text('Dónde está cada cosa'), findsOneWidget);
    expect(find.text('1 de ${defaultTour.length}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tour-next')));
    await settle(tester);

    expect(find.text('Dónde va lo que escribes'), findsOneWidget);
    expect(find.text('Dónde está cada cosa'), findsNothing);
  });

  testWidgets('salirse lo da por hecho', (tester) async {
    // Cerrarlo es una respuesta, no una interrupción: volver a ofrecerlo en
    // el siguiente arranque sería no haberla entendido.
    var apuntado = false;
    final tour = await pumpShell(
      tester,
      onFinished: () async {
        apuntado = true;
      },
    );
    tour.start();
    await settle(tester);

    await tester.tap(find.byKey(const Key('tour-skip')));
    await settle(tester);

    expect(tour.running, isFalse);
    expect(apuntado, isTrue);
    expect(find.text('Dónde está cada cosa'), findsNothing);
  });

  testWidgets('llegar al final también', (tester) async {
    var apuntado = false;
    final tour = await pumpShell(
      tester,
      steps: const [
        TourStep(id: 'rail', title: 'Uno', body: 'El carril.'),
        TourStep(id: 'sync', title: 'Dos', body: 'La barra.'),
      ],
      onFinished: () async {
        apuntado = true;
      },
    );
    tour.start();
    await settle(tester);

    expect(find.text('Uno'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tour-next')));
    await settle(tester);
    expect(find.text('Dos'), findsOneWidget);
    // El último dice «Listo» y no «Siguiente».
    expect(find.text('Listo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tour-next')));
    await settle(tester);

    expect(tour.running, isFalse);
    expect(apuntado, isTrue);
  });

  testWidgets('un paso cuyo objetivo no está se salta', (tester) async {
    // Pasa de verdad: en una ventana estrecha el carril es una barra de
    // abajo y sus destinos no están marcados. Un tour que señala el vacío es
    // peor que uno corto.
    final tour = await pumpShell(
      tester,
      steps: const [
        TourStep(id: 'no-existe', title: 'Fantasma', body: 'No está.'),
        TourStep(id: 'sync', title: 'La barra', body: 'Esto sí está.'),
      ],
    );
    tour.start();
    await settle(tester);

    expect(find.text('Fantasma'), findsNothing);
    expect(find.text('La barra'), findsOneWidget);
  });

  testWidgets('sin ningún objetivo montado, no se enseña nada', (tester) async {
    var apuntado = false;
    final tour = await pumpShell(
      tester,
      steps: const [
        TourStep(id: 'no-existe', title: 'Fantasma', body: 'No está.'),
      ],
      onFinished: () async {
        apuntado = true;
      },
    );
    tour.start();
    await settle(tester);

    expect(tour.running, isFalse);
    expect(find.text('Fantasma'), findsNothing);
    // Y se apunta como hecho: ofrecer en cada arranque un tour que no puede
    // enseñar nada es peor que no tenerlo.
    expect(apuntado, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('cambiando de pantalla', () {
    // Sin router de verdad: una dirección en un `ValueNotifier` y una
    // pantalla que enseña su objetivo solo cuando se está en ella. Es lo que
    // hace falta para ver que el tour va, espera y vuelve.
    Future<({TourController tour, ValueNotifier<String> at})> pumpPlaces(
      WidgetTester tester,
      List<TourStep> steps, {
      Future<void> Function()? onFinished,
    }) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tourTargets.clear();

      final catalogue = catalogueWith(defaultUnits());
      final session = FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogue,
      );
      await session.primeForTest(catalogue);

      final at = ValueNotifier('/');
      final tour = TourController(steps: steps, onFinished: onFinished)
        ..attach(
          navigate: (location) => at.value = location,
          locate: () => at.value,
          session: session,
        );

      await tester.pumpWidget(
        MaterialApp(
          theme: didactaTheme(),
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
              TourOverlay(controller: tour),
            ],
          ),
          home: Stack(
            children: [
              Scaffold(
                body: ValueListenableBuilder<String>(
                  valueListenable: at,
                  builder: (context, location, _) => Column(
                    children: [
                      TourTarget(
                        id: 'siempre',
                        child: const SizedBox(width: 200, height: 40),
                      ),
                      if (location == '/otra')
                        TourTarget(
                          id: 'otra',
                          child: const SizedBox(width: 200, height: 40),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      return (tour: tour, at: at);
    }

    testWidgets('va a la pantalla del paso, y al acabar vuelve', (
      tester,
    ) async {
      var apuntado = false;
      final it = await pumpPlaces(tester, [
        const TourStep(id: 'siempre', title: 'Aquí', body: 'En el armazón.'),
        TourStep(
          id: 'otra',
          title: 'Allí',
          body: 'En otra pantalla.',
          place: (_) => '/otra',
        ),
      ], onFinished: () async => apuntado = true);

      it.tour.start();
      await settle(tester);
      expect(find.text('Aquí'), findsOneWidget);
      expect(it.at.value, '/');

      await tester.tap(find.byKey(const Key('tour-next')));
      await settle(tester);
      expect(it.at.value, '/otra');
      expect(find.text('Allí'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tour-next')));
      await settle(tester);
      // A donde se estaba: dejar a alguien en una pantalla que no ha elegido
      // es dejarle perdido justo al acabar de orientarle.
      expect(it.at.value, '/');
      expect(it.tour.running, isFalse);
      expect(apuntado, isTrue);
    });

    testWidgets('un sitio que no hay se salta', (tester) async {
      // Sin asignaturas no hay curso que enseñar, y el capítulo entero se
      // salta en lugar de señalar una pantalla vacía.
      final it = await pumpPlaces(tester, [
        TourStep(
          id: 'otra',
          title: 'Sin sitio',
          body: 'No hay a dónde ir.',
          place: (_) => null,
        ),
        const TourStep(id: 'siempre', title: 'Aquí', body: 'En el armazón.'),
      ]);

      it.tour.start();
      await settle(tester);

      expect(find.text('Sin sitio'), findsNothing);
      expect(find.text('Aquí'), findsOneWidget);
      expect(it.at.value, '/');
    });

    testWidgets('un objetivo que no llega a salir se salta, esperándolo', (
      tester,
    ) async {
      final it = await pumpPlaces(tester, [
        TourStep(
          id: 'nunca',
          title: 'Nunca',
          body: 'La pantalla no lo tiene.',
          place: (_) => '/otra',
        ),
        const TourStep(id: 'siempre', title: 'Aquí', body: 'En el armazón.'),
      ]);

      it.tour.start();
      // Lo que espera a una pantalla que carga: unos segundos, no más.
      for (var i = 0; i < 12; i += 1) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(find.text('Nunca'), findsNothing);
      expect(find.text('Aquí'), findsOneWidget);
    });

    testWidgets('«Atrás» vuelve al paso anterior y a su pantalla', (
      tester,
    ) async {
      final it = await pumpPlaces(tester, [
        TourStep(
          id: 'otra',
          title: 'Allí',
          body: 'En otra pantalla.',
          place: (_) => '/otra',
        ),
        TourStep(
          id: 'siempre',
          title: 'Aquí',
          body: 'De vuelta.',
          place: (_) => '/',
        ),
      ]);

      it.tour.start();
      await settle(tester);
      expect(find.text('Allí'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tour-next')));
      await settle(tester);
      expect(find.text('Aquí'), findsOneWidget);
      expect(it.at.value, '/');

      await tester.tap(find.byKey(const Key('tour-back')));
      await settle(tester);
      expect(find.text('Allí'), findsOneWidget);
      expect(it.at.value, '/otra');
    });
  });
}
