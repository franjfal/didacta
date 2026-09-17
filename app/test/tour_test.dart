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
        home: Stack(
          children: [
            const DidactaShell(location: '/', child: SizedBox.shrink()),
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

    expect(find.text('Cuatro sitios'), findsOneWidget);
    expect(find.text('1 de ${defaultTour.length}'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tour-next')));
    await settle(tester);

    expect(find.text('La biblioteca'), findsOneWidget);
    expect(find.text('Cuatro sitios'), findsNothing);
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
    expect(find.text('Cuatro sitios'), findsNothing);
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
}
