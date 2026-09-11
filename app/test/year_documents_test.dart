/// Los grupos de contenido de un año: ordenarlos, crearlos y quitarlos.
///
/// Lo que hay que demostrar aquí es que el fichero sale bien, porque es lo
/// único que queda después: la pantalla se cierra y lo que permanece es
/// `year.yaml`. Así que cada test acaba mirando el texto que se ha
/// commiteado, no el estado del widget.
@TestOn('vm')
library;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/composition_file.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

final Finder save = find.byKey(const Key('documents-save'));
final Finder commit = find.byKey(const Key('composition-commit'));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<FakeGateway> pumpYear(
  WidgetTester tester, {
  FakeGateway? gateway,
}) async {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final used = gateway ?? FakeGateway();
  final catalogue = catalogueWith(defaultUnits());
  final session = FakeSession(gatewayOverride: used, catalogue: catalogue);
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
  return used;
}

List<String> committedIds(FakeGateway gateway) =>
    CompositionFile(gateway.commits.last.text).documentIds();

void main() {
  testWidgets('los grupos salen en el orden del fichero', (tester) async {
    await pumpYear(tester);
    expect(find.text('Tema 1. Espacios normados'), findsOneWidget);
    expect(find.text('Hoja 1'), findsOneWidget);
    // Y no hay nada que guardar todavía.
    expect(save, findsNothing);
  });

  testWidgets('arrastrar cambia el orden y lo guarda', (tester) async {
    final gateway = await pumpYear(tester);

    // El asa de la segunda fila, arrastrada por encima de la primera. Como
    // gesto explícito y no con `tester.drag`: una lista reordenable sigue al
    // puntero, y un salto de golpe no llega a empezar el arrastre.
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(2));
    final from = tester.getCenter(handles.at(1));
    final to = tester.getCenter(handles.at(0));

    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout);
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(Offset.lerp(from, to, step / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.moveTo(to - const Offset(0, 8));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await settle(tester);

    expect(save, findsOneWidget, reason: 'el arrastre no ha cambiado nada');
    await tester.tap(save);
    await settle(tester);
    // El mensaje dice lo que pasó, no «editar year.yaml».
    expect(find.textContaining('Cambiar el orden de los grupos'), findsWidgets);
    await tester.tap(commit);
    await settle(tester);

    expect(committedIds(gateway), ['hoja-1', 'tema-1']);
    // Y el bloque se ha movido entero: la entrada comentada sigue dentro de
    // tema-1, que es lo que separa mover de reescribir.
    expect(
      gateway.commits.single.text,
      contains('      # - unit: analysis/normed/dedekind'),
    );
    expect(gateway.commits.single.text, contains('          # TODO: va'));
  });

  testWidgets('un grupo nuevo se crea vacío y con su tipo', (tester) async {
    final gateway = await pumpYear(tester);

    await tester.tap(find.byKey(const Key('add-document')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('new-document-title')),
      'Tema 3. Series de funciones',
    );
    await settle(tester);
    // El identificador sale del título.
    final id = tester.widget<TextField>(
      find.byKey(const Key('new-document-id')),
    );
    expect(id.controller!.text, 'tema-3-series-de-funciones');

    await tester.tap(find.byKey(const Key('kind-seminar')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-new-document')));
    await settle(tester);

    await tester.tap(save);
    await settle(tester);
    expect(find.textContaining('Añadir el grupo'), findsWidgets);
    await tester.tap(commit);
    await settle(tester);

    final text = gateway.commits.single.text;
    expect(committedIds(gateway), [
      'tema-1',
      'hoja-1',
      'tema-3-series-de-funciones',
    ]);
    expect(text, contains('    kind: seminar'));
    expect(text, contains('      es: Tema 3. Series de funciones'));
    // Los demás idiomas, marcados como pendientes **en un comentario**: un
    // `va: TODO` sería un título de verdad y saldría en la lista y en el PDF.
    expect(text, contains('      # TODO: va'));
    expect(text, contains('      # TODO: en'));
    expect(text, isNot(contains('va: TODO')));
    // Vacío, y diciéndolo.
    expect(text, contains('    structure: []'));
    // Y el resto del fichero intacto.
    expect(text, contains('  - id: hoja-1'));
  });

  testWidgets('un identificador que ya existe no deja crear', (tester) async {
    await pumpYear(tester);
    await tester.tap(find.byKey(const Key('add-document')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('new-document-title')),
      'Otra cosa',
    );
    await settle(tester);
    await tester.enterText(find.byKey(const Key('new-document-id')), 'hoja-1');
    await settle(tester);

    expect(find.textContaining('Ya hay un grupo'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-new-document')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('quitar pregunta antes, y dice qué no se toca', (tester) async {
    final gateway = await pumpYear(tester);

    await tester.tap(find.byKey(const Key('remove-document-hoja-1')));
    await settle(tester);
    expect(find.textContaining('Las unidades no se tocan'), findsOneWidget);

    // Cancelar no cambia nada.
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(save, findsNothing);

    await tester.tap(find.byKey(const Key('remove-document-hoja-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-remove-document')));
    await settle(tester);
    await tester.tap(save);
    await settle(tester);
    expect(find.textContaining('Quitar el grupo hoja-1'), findsWidgets);
    await tester.tap(commit);
    await settle(tester);

    expect(committedIds(gateway), ['tema-1']);
    expect(gateway.commits.single.text, isNot(contains('Hoja 1')));
    // El vecino, entero.
    expect(
      gateway.commits.single.text,
      contains('      # - unit: analysis/normed/dedekind'),
    );
  });

  testWidgets('sin permiso de escritura no se arrastra ni se añade', (
    tester,
  ) async {
    await pumpYear(tester, gateway: FakeGateway(writable: false));
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.byKey(const Key('add-document')), findsNothing);
    expect(find.byKey(const Key('remove-document-hoja-1')), findsNothing);
    // Pero se sigue viendo lo que hay.
    expect(find.text('Hoja 1'), findsOneWidget);
  });

  testWidgets('descartar vuelve al fichero como estaba', (tester) async {
    final gateway = await pumpYear(tester);

    await tester.tap(find.byKey(const Key('remove-document-hoja-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-remove-document')));
    await settle(tester);
    expect(save, findsOneWidget);

    await tester.tap(find.text('Descartar'));
    await settle(tester);

    expect(save, findsNothing);
    expect(find.text('Hoja 1'), findsOneWidget);
    expect(gateway.commits, isEmpty);
  });
}
