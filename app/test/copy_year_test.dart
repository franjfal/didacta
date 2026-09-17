/// Copiar documentos de un curso a otro, desde la pantalla.
///
/// Lo que importa aquí es lo que se le pide al motor, porque es lo único que
/// queda después: la pantalla se cierra y lo que permanece son los ficheros.
/// Así que cada test acaba mirando los argumentos con los que se llamó, no el
/// estado del widget.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/course_admin_ui.dart';
import 'package:didacta_app/ui/theme.dart';

import 'fixture.dart';

Document doc(String id, {String kind = 'theory', int units = 2}) => Document(
  id: id,
  kind: kind,
  language: 'es',
  titles: {'es': 'Título de $id'},
  profiles: const [],
  unitRefs: [for (var i = 0; i < units; i += 1) 'a/b/u$i'],
);

Course course() => Course(
  id: 'am-i',
  titles: const {'es': 'Análisis Matemático I'},
  language: 'es',
  years: {
    '2022-2023': CourseYear(
      year: '2022-2023',
      language: 'es',
      documents: [
        doc('tema-1'),
        doc('faq', kind: 'handout', units: 0),
      ],
    ),
    '2026-2027': const CourseYear(
      year: '2026-2027',
      language: 'es',
      documents: [],
    ),
  },
);

Future<CopyRequest?> open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  CopyRequest? answer;
  final subject = course();
  await tester.pumpWidget(
    ChangeNotifierProvider<Session>.value(
      value: FakeSession(
        gatewayOverride: FakeGateway(),
        catalogue: catalogueWith(defaultUnits()),
      ),
      child: MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showDialog<CopyRequest>(
                  context: context,
                  builder: (context) => CopyYearDialog(
                    course: subject,
                    year: '2022-2023',
                    entry: subject.years['2022-2023']!,
                    language: 'es',
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  testWidgets('enseña los documentos del curso, para elegir cuáles', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Título de tema-1'), findsOneWidget);
    expect(find.text('Título de faq'), findsOneWidget);
  });

  testWidgets('ofrece los demás cursos, y no este', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('copy-to-2026-2027')), findsOneWidget);
    expect(find.byKey(const Key('copy-to-2022-2023')), findsNothing);
  });

  testWidgets('sin curso de destino no deja copiar', (tester) async {
    // Vienen todos marcados, así que lo único que falta es a dónde: el botón
    // tiene que decir que falta, no copiar a ningún sitio.
    await open(tester);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('copy-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('elegir destino y confirmar devuelve lo marcado', (tester) async {
    late CopyRequest? answer;
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final subject = course();
    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showDialog<CopyRequest>(
                  context: context,
                  builder: (context) => CopyYearDialog(
                    course: subject,
                    year: '2022-2023',
                    entry: subject.years['2022-2023']!,
                    language: 'es',
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Se desmarca uno, se elige destino y se confirma.
    await tester.tap(find.byKey(const Key('copy-doc-faq')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-to-2026-2027')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-confirm')));
    await tester.pumpAndSettle();

    expect(answer?.toYear, '2026-2027');
    expect(answer?.documents, ['tema-1']);
  });

  testWidgets('sin nada marcado tampoco deja copiar', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('copy-none')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-to-2026-2027')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('copy-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('dice que las unidades no se duplican', (tester) async {
    // Es la propiedad por la que esto existe, y la que alguien necesita leer
    // antes de darle: copiar un curso no reparte copias de su material.
    await open(tester);
    expect(find.textContaining('no se duplican'), findsOneWidget);
  });
}
