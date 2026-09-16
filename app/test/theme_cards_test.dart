/// Las tarjetas de tema en la pantalla de un curso.
///
/// La pregunta que la pantalla no contestaba y ahora sí: **qué entra en el
/// Tema 1**. Su teoría, su práctica, su análisis bibliográfico y su marco
/// histórico, que además viven en repositorios distintos. Con una lista
/// corrida eso no se ve.
///
/// Lo que se prueba es lo visible --que la tarjeta agrupa, que se pliega, y
/// que lo que no tiene tema sigue estando-- porque es lo que se rompería sin
/// que ningún test de modelo se enterara.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:didacta_app/data/preferences.dart';
import 'package:didacta_app/model/catalogue.dart';
import 'package:didacta_app/state/session.dart';
import 'package:didacta_app/ui/theme.dart';
import 'package:didacta_app/ui/year_page.dart';

import 'fixture.dart';

/// Un curso con dos temas declarados y un documento fuera de ellos.
Map<String, dynamic> themedCourse() => {
  'id': 'am-iii',
  'title': const {'es': 'Análisis Matemático III'},
  'language': 'es',
  'years': {
    '2025-2026': {
      'year': '2025-2026',
      'language': 'es',
      'themes': const [
        {
          'id': 'tema-1',
          'title': {'es': 'Tema 1: espacios normados'},
        },
        {
          'id': 'tema-2',
          'title': {'es': 'Tema 2: sucesiones'},
        },
      ],
      'documents': [
        {
          'id': 'tema-1',
          'kind': 'theory',
          'language': 'es',
          'title': const {'es': 'Teoría del tema 1'},
          'themes': const ['tema-1'],
          'unitRefs': const <String>[],
        },
        {
          'id': 'hoja-1',
          'kind': 'problems',
          'language': 'es',
          'title': const {'es': 'Hoja 1'},
          'themes': const ['tema-1'],
          'unitRefs': const <String>[],
        },
        {
          'id': 'hoja-2',
          'kind': 'problems',
          'language': 'es',
          'title': const {'es': 'Hoja 2'},
          'themes': const ['tema-2'],
          'unitRefs': const <String>[],
        },
        {
          'id': 'faq',
          'kind': 'handout',
          'language': 'es',
          'title': const {'es': 'Preguntas frecuentes'},
          'unitRefs': const <String>[],
        },
      ],
    },
  },
};

/// El mismo tema, repartido entre dos repositorios: la teoría lo declara y
/// los problemas lo nombran, que es la forma que tiene el material real.
Catalogue splitCatalogue() {
  Map<String, dynamic> course(List<Map<String, dynamic>> documents,
      {bool declares = false}) => {
    'id': 'am-iii',
    'title': const {'es': 'Análisis Matemático III'},
    'language': 'es',
    'years': {
      '2025-2026': {
        'year': '2025-2026',
        'language': 'es',
        if (declares)
          'themes': const [
            {
              'id': 'tema-1',
              'title': {'es': 'Tema 1: espacios normados'},
            },
          ],
        'documents': documents,
      },
    },
  };

  final problemas = catalogueWith(
    const [],
    courses: [
      course([
        {
          'id': 'hoja-1',
          'kind': 'problems',
          'language': 'es',
          'title': const {'es': 'Hoja 1'},
          'themes': const ['tema-1'],
          'unitRefs': const <String>[],
        },
      ]),
    ],
    repo: 'x/problemas',
  );
  final teoria = catalogueWith(
    const [],
    courses: [
      course(declares: true, [
        {
          'id': 'tema-1',
          'kind': 'theory',
          'language': 'es',
          'title': const {'es': 'Teoría del tema 1'},
          'themes': const ['tema-1'],
          'unitRefs': const <String>[],
        },
      ]),
    ],
    repo: 'x/teoria',
  );
  return Catalogue.merge([problemas, teoria]);
}

Future<FakeSession> pumpSplit(WidgetTester tester) async {
  final catalogue = splitCatalogue();
  final session = FakeSession(
    // Una composición vacía: aquí se prueba lo que enseña el catálogo, y la
    // pasarela de mentira da el mismo fichero a los dos repositorios, así que
    // sus documentos saldrían dos veces.
    gatewayOverride: FakeGateway(
      files: {
        'courses/am-iii/2025-2026/year.yaml':
            'course: am-iii\nyear: 2025-2026\nlanguage: es\n\ndocuments:\n',
      },
    ),
    catalogue: catalogue,
    preferencesOverride: MemoryPreferences(),
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
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return session;
}

Future<FakeSession> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final catalogue = catalogueWith(defaultUnits(), courses: [themedCourse()]);
  final session = FakeSession(
    gatewayOverride: FakeGateway(),
    catalogue: catalogue,
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
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return session;
}

void main() {
  testWidgets('los temas salen en tarjetas, con lo que llevan dentro', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Tema 1: espacios normados'), findsOneWidget);
    expect(find.text('Tema 2: sucesiones'), findsOneWidget);
    expect(find.text('Teoría del tema 1'), findsOneWidget);
    expect(find.text('Hoja 1'), findsOneWidget);
    expect(find.text('Hoja 2'), findsOneWidget);
  });

  testWidgets('la cabecera dice cuántos documentos lleva', (tester) async {
    await pump(tester);
    expect(find.text('2 documentos'), findsOneWidget);
    expect(find.text('1 documento'), findsOneWidget);
  });

  testWidgets('lo que no está en ningún tema sigue estando, sin tarjeta', (
    tester,
  ) async {
    // Es la mitad del trato: agrupar no puede esconder lo que no se agrupa.
    await pump(tester);
    expect(find.text('Preguntas frecuentes'), findsOneWidget);
  });

  testWidgets('plegar un tema esconde lo suyo y no lo demás', (tester) async {
    final session = await pump(tester);

    await tester.tap(find.byKey(const Key('theme-header-tema-1')));
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Teoría del tema 1'), findsNothing);
    expect(find.text('Hoja 1'), findsNothing);
    // El título del tema se queda: plegado no es escondido.
    expect(find.text('Tema 1: espacios normados'), findsOneWidget);
    // Y lo de los demás temas ni se entera.
    expect(find.text('Hoja 2'), findsOneWidget);
    expect(find.text('Preguntas frecuentes'), findsOneWidget);

    expect(session.collapsedThemes('am-iii', '2025-2026'), {'tema-1'});
  });

  testWidgets('desplegar lo devuelve', (tester) async {
    await pump(tester);
    final header = find.byKey(const Key('theme-header-tema-1'));

    await tester.tap(header);
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(header);
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Teoría del tema 1'), findsOneWidget);
  });
  testWidgets('apagar un repositorio no deja rastros en gris', (tester) async {
    // Lo que pasaba: su `year.yaml` se seguía leyendo, así que sus documentos
    // quedaban en la lista del fichero y fuera del catálogo --que es la forma
    // exacta de un documento recién creado-- y salían en gris, a medias.
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = await pumpSplit(tester);

    expect(find.text('Teoría del tema 1'), findsOneWidget);
    expect(find.text('Hoja 1'), findsOneWidget);
    expect(find.text('2 documentos'), findsOneWidget);

    await session.setRepoVisible('x/teoria', false);
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Teoría del tema 1'), findsNothing);
    expect(find.text('Hoja 1'), findsOneWidget);
    // Y como el tema lo declaraba ese repositorio, la tarjeta se va con él:
    // apagar enseña lo mismo que no tener, y quien no tiene la teoría no
    // sabe que existe un Tema 1.
    expect(find.text('Tema 1: espacios normados'), findsNothing);
  });

  testWidgets('apagar un repositorio dice cuánto se está escondiendo', (
    tester,
  ) async {
    // Con el tema todavía declarado --se apaga el otro repositorio-- la
    // tarjeta se queda, y tiene que decir que le falta algo: esconder la
    // mitad de un tema en silencio es peor que no agrupar.
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = await pumpSplit(tester);
    expect(find.text('2 documentos'), findsOneWidget);

    await session.setRepoVisible('x/problemas', false);
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Hoja 1'), findsNothing);
    expect(find.text('Teoría del tema 1'), findsOneWidget);
    expect(find.text('1 de 2 documentos'), findsOneWidget);
  });
  testWidgets('el botón de abajo crea un tema, no un documento', (
    tester,
  ) async {
    // Lo que había: creaba un documento, y había que decir después a qué tema
    // pertenecía -- que es el paso que se olvida. El tema es el nivel que se
    // crea primero.
    await pump(tester);

    expect(find.text('Nuevo tema'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-theme')));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo tema'), findsWidgets);
    expect(find.byKey(const Key('new-theme-title')), findsOneWidget);
  });

  testWidgets('el identificador del tema sale del título', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('add-theme')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('new-theme-title')),
      'Tema 3: series numéricas',
    );
    await tester.pumpAndSettle();

    final id = tester.widget<TextField>(
      find.byKey(const Key('new-theme-id')),
    );
    expect(id.controller!.text, 'tema-3-series-numericas');
  });

  testWidgets('cada tema tiene su botón para crear un documento dentro', (
    tester,
  ) async {
    // Creado desde el tema ya sabe a cuál pertenece.
    await pump(tester);
    expect(find.byKey(const Key('add-document-tema-1')), findsOneWidget);
    expect(find.byKey(const Key('add-document-tema-2')), findsOneWidget);
  });

  testWidgets('y queda uno para lo que no es de ningún tema', (tester) async {
    // La FAQ, la notación, el calendario: existen, así que tienen por dónde
    // crearse.
    await pump(tester);
    expect(find.text('Documento suelto'), findsOneWidget);
  });
  testWidgets('un tema recién creado sale, vacío y con su botón', (
    tester,
  ) async {
    // El fallo que tenía: un tema declarado y sin documentos no se dibujaba,
    // así que crearlo y verlo desaparecer era lo normal -- y sin tarjeta no
    // había por dónde meterle el primer documento.
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final catalogue = catalogueWith(
      defaultUnits(),
      courses: [
        {
          'id': 'am-iii',
          'title': const {'es': 'Análisis Matemático III'},
          'language': 'es',
          'years': {
            '2025-2026': {
              'year': '2025-2026',
              'language': 'es',
              'themes': const [
                {
                  'id': 'tema-9',
                  'title': {'es': 'Tema 9: recién creado'},
                },
              ],
              'documents': const <Map<String, dynamic>>[],
            },
          },
        },
      ],
    );
    final session = FakeSession(
      gatewayOverride: FakeGateway(
        files: {
          'courses/am-iii/2025-2026/year.yaml':
              'course: am-iii\nyear: 2025-2026\nlanguage: es\n\ndocuments:\n',
        },
      ),
      catalogue: catalogue,
      preferencesOverride: MemoryPreferences(),
    );
    await session.primeForTest(catalogue);
    // Un repositorio abierto: el año no tiene documentos, así que de dónde
    // sale en cuál escribir es justo lo que se está probando.
    await session.useCloneForTest('/tmp/didacta-test');

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
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Tema 9: recién creado'), findsOneWidget);
    expect(find.text('0 documentos'), findsOneWidget);
    expect(find.byKey(const Key('add-document-tema-9')), findsOneWidget);
  });
  testWidgets('hay un botón de compilar en cada nivel', (tester) async {
    // El mismo gesto en los tres sitios: el curso entero, un tema, un
    // documento. Que sea el mismo icono en todos es lo que lo hace
    // aprendible.
    await pump(tester);

    expect(find.byKey(const Key('build-year')), findsOneWidget);
    expect(find.byKey(const Key('build-theme-tema-1')), findsOneWidget);
    expect(find.byKey(const Key('build-theme-tema-2')), findsOneWidget);
    expect(find.byKey(const Key('build-document-tema-1')), findsOneWidget);
    expect(find.byKey(const Key('build-document-hoja-1')), findsOneWidget);
  });

  testWidgets('sin PDF compilado no hay atajo para abrirlo', (tester) async {
    // Un atajo que lleva a un fichero que no está es peor que no tenerlo.
    await pump(tester);
    expect(find.byKey(const Key('open-pdf-tema-1')), findsNothing);
  });
}
