/// El diálogo de exportar un curso.
///
/// Lo que importa es lo que sale de aquí, porque es lo que se le pide al
/// motor: qué idiomas, qué documentos y si hay que compilar antes.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/ui/export_year.dart';
import 'package:didacta_app/ui/theme.dart';

Document doc(String id, {List<String> themes = const []}) => Document(
  id: id,
  kind: 'theory',
  language: 'es',
  titles: {'es': 'Título de $id'},
  profiles: const [],
  unitRefs: const [],
  themes: themes,
);

CourseYear entry() => CourseYear(
  year: '2026-2027',
  language: 'es',
  themes: const [
    CourseTheme(id: 'tema-1', titles: {'es': 'Tema 1'}),
    CourseTheme(id: 'tema-2', titles: {'es': 'Tema 2'}),
  ],
  documents: [
    doc('teoria-1', themes: const ['tema-1']),
    doc('hoja-1', themes: const ['tema-1']),
    doc('teoria-2', themes: const ['tema-2']),
    doc('faq'),
  ],
);

Future<ExportRequest?> open(
  WidgetTester tester, {
  List<String> languages = const ['es', 'va'],
}) async {
  tester.view.physicalSize = const Size(1100, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  ExportRequest? answer;
  await tester.pumpWidget(
    MaterialApp(
      theme: didactaTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showDialog<ExportRequest>(
                context: context,
                builder: (context) => ExportYearDialog(
                  course: Course(
                    id: 'am-i',
                    titles: const {'es': 'AM I'},
                    language: 'es',
                    years: {'2026-2027': entry()},
                  ),
                  year: '2026-2027',
                  entry: entry(),
                  languages: languages,
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
  return answer;
}

void main() {
  testWidgets('enseña los temas y lo que llevan dentro', (tester) async {
    await open(tester);
    expect(find.text('Tema 1'), findsOneWidget);
    expect(find.text('Tema 2'), findsOneWidget);
    expect(find.text('Título de teoria-1'), findsOneWidget);
    // Lo que no está en ningún tema también se puede exportar.
    expect(find.text('Sin tema'), findsOneWidget);
    expect(find.text('Título de faq'), findsOneWidget);
  });

  testWidgets('todo viene marcado, que es lo que se quiere casi siempre', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Exportar 4'), findsOneWidget);
  });

  testWidgets('el primer idioma viene marcado y los demás no', (tester) async {
    // Un reparto es de un idioma; los demás se añaden si se quieren.
    await open(tester);
    final es = tester.widget<FilterChip>(
      find.byKey(const Key('export-language-es')),
    );
    final va = tester.widget<FilterChip>(
      find.byKey(const Key('export-language-va')),
    );
    expect(es.selected, isTrue);
    expect(va.selected, isFalse);
  });

  testWidgets('desmarcar un tema desmarca lo suyo', (tester) async {
    // Marcar por tema es lo que hace esto rápido: un curso son treinta
    // documentos y seis temas.
    await open(tester);
    expect(find.text('Exportar 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-theme-tema-1')));
    await tester.pumpAndSettle();
    expect(find.text('Exportar 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('export-theme-tema-1')));
    await tester.pumpAndSettle();
    expect(find.text('Exportar 4'), findsOneWidget);
  });

  testWidgets('lo elegido es lo que sale', (tester) async {
    ExportRequest? answer;
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: didactaTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showDialog<ExportRequest>(
                  context: context,
                  builder: (context) => ExportYearDialog(
                    course: Course(
                      id: 'am-i',
                      titles: const {'es': 'AM I'},
                      language: 'es',
                      years: {'2026-2027': entry()},
                    ),
                    year: '2026-2027',
                    entry: entry(),
                    languages: const ['es', 'va'],
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

    await tester.tap(find.byKey(const Key('export-document-faq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-language-va')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-rebuild')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-confirm')));
    await tester.pumpAndSettle();

    expect(answer?.languages, ['es', 'va']);
    expect(answer?.documents, ['teoria-1', 'hoja-1', 'teoria-2']);
    expect(answer?.rebuild, isTrue);
  });

  testWidgets('sin nada marcado no deja exportar', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('export-toggle-all')));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('export-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('sin idioma tampoco', (tester) async {
    await open(tester, languages: const ['es']);
    await tester.tap(find.byKey(const Key('export-language-es')));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('export-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('compilar antes viene apagado', (tester) async {
    // Un curso entero son cuarenta salidas: quien acaba de compilarlo no
    // quiere repetirlo por exportar.
    await open(tester);
    final box = tester.widget<CheckboxListTile>(
      find.byKey(const Key('export-rebuild')),
    );
    expect(box.value, isFalse);
  });
}
