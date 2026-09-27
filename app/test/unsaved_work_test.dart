/// Salir con algo escrito y sin guardar pregunta antes.
///
/// No había ningún aviso: cambiar de lección, de pantalla o cerrar con un
/// párrafo a medio escribir se lo llevaba sin decir nada. Esto monta la
/// aplicación entera, con su router, porque la pregunta la hace el router al
/// salir de la pantalla y no la pantalla.
@TestOn('vm')
library;

import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:didacta_app/router.dart';
import 'package:didacta_app/state/unsaved_work.dart';
import 'package:didacta_app/ui/shell.dart';

import 'fixture.dart';
import 'platform_menus_test.dart' show pumpApp, settle, where;

GoRouter routerOf(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(DidactaShell)));

Future<void> openLessonAndType(WidgetTester tester) async {
  routerOf(tester).go(Routes.unit(unitPath));
  await settle(tester);
  final field = find.byType(EditableText).first;
  await tester.enterText(field, 'Un párrafo a medio escribir.');
  await settle(tester);
}

void main() {
  group('el registro', () {
    test('cada pantalla pregunta por lo suyo', () {
      final work = UnsavedWork()
        ..mark(1, 'la lección', place: '/unit/a/b')
        ..mark(2, 'el curso', place: '/courses/x/2025-2026');
      expect(work.whatAt('/unit/a/b'), ['la lección']);
      expect(work.whatAt('/unit/a/b?lang=va'), ['la lección']);
      expect(work.whatAt('/courses'), isEmpty);
      work.mark(1, null);
      expect(work.what, ['el curso']);
    });
  });

  testWidgets('cambiar de pantalla con cambios pregunta, y se puede quedar', (
    tester,
  ) async {
    await pumpApp(tester);
    await openLessonAndType(tester);

    routerOf(tester).go(Routes.library());
    await settle(tester);
    expect(find.text('Hay cambios sin guardar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unsaved-stay')));
    await settle(tester);
    expect(where(tester), Routes.unit(unitPath));
    // Y lo escrito sigue ahí.
    expect(find.text('Un párrafo a medio escribir.'), findsOneWidget);
  });

  testWidgets('o salir sin guardar, si se dice', (tester) async {
    await pumpApp(tester);
    await openLessonAndType(tester);

    routerOf(tester).go(Routes.library());
    await settle(tester);
    await tester.tap(find.byKey(const Key('unsaved-leave')));
    await settle(tester);
    expect(where(tester), Routes.library());
  });

  testWidgets('sin cambios no pregunta nada', (tester) async {
    await pumpApp(tester);
    routerOf(tester).go(Routes.unit(unitPath));
    await settle(tester);

    routerOf(tester).go(Routes.library());
    await settle(tester);
    expect(find.text('Hay cambios sin guardar'), findsNothing);
    expect(where(tester), Routes.library());
  });

  testWidgets('cerrar Didacta con cambios también pregunta', (tester) async {
    await pumpApp(tester);
    await openLessonAndType(tester);

    // Lo que hace el sistema al pulsar ⌘Q o cerrar la ventana.
    final answer = tester.binding.handleRequestAppExit();
    await settle(tester);
    expect(find.text('Cerrar sin guardar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsaved-stay')));
    await settle(tester);
    expect(await answer, AppExitResponse.cancel);
  });
}
